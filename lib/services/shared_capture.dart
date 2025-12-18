import 'dart:convert';
import 'package:http/http.dart' as http;
import 'token_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SharedCaptureService {
  final String _baseUrl;

  // ignore: unused_field
  final String _globalUrl =
      "https://ditrix-attendance-scanner-server.onrender.com";

  SharedCaptureService(
      {String? baseUrl =
          'https://ditrix-attendance-scanner-server.onrender.com'})
      : _baseUrl = baseUrl ?? 'http://localhost:3000';

  Future<String?> _getFirebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  Future<Map<String, dynamic>> listCaptures() async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) throw Exception("Not authenticated");

    final response = await http.get(
      Uri.parse('$_baseUrl/shared-captures'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to list captures: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createCapture({
    required String id,
    required String subject,
    required String date,
    required String startTime,
    required String endTime,
    List<Map<String, dynamic>>? roster,
  }) async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http
        .post(
          Uri.parse('$_baseUrl/shared-captures'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'id': id,
            'subject': subject,
            'date': date,
            'start_time': startTime,
            'end_time': endTime,
            'roster': roster,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 409) {
      // Duplicate upload
      final data = jsonDecode(response.body);
      throw Exception(
          data['message'] ?? 'This capture has already been uploaded');
    }

    if (response.statusCode != 201) {
      throw Exception('Failed to create capture: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCapture(String id) async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/shared-captures/$id'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to get capture: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> updateCapture(
    String id, {
    String? subject,
    String? date,
    String? startTime,
    String? endTime,
    List<Map<String, dynamic>>? roster,
  }) async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{};
    if (subject != null) body['subject'] = subject;
    if (date != null) body['date'] = date;
    if (startTime != null) body['start_time'] = startTime;
    if (endTime != null) body['end_time'] = endTime;
    if (roster != null) body['roster'] = roster;

    final response = await http
        .patch(
          Uri.parse('$_baseUrl/shared-captures/$id'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to update capture: ${response.statusCode}');
    }
  }

  Future<void> deleteCapture(String id) async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$_baseUrl/shared-captures/$id'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to delete capture: ${response.statusCode}');
    }
  }

  Future<String> joinByCode(String code) async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/shared-captures/join/$code'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to join: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return data['capture_id'] as String;
  }

  Future<void> addCollaborator(String captureId, String email,
      {String role = 'viewer'}) async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http
        .post(
          Uri.parse('$_baseUrl/shared-captures/$captureId/collaborators'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'email': email, 'role': role}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to add collaborator: ${response.statusCode}');
    }
  }

  Future<void> removeCollaborator(String captureId, int userId) async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$_baseUrl/shared-captures/$captureId/collaborators/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to remove collaborator: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> getAllStudents() async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/shared-captures/students/list'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to get students: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return List<Map<String, dynamic>>.from(data['students'] ?? []);
  }
}
