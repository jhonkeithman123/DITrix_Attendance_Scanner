// ...existing code...
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Replace localhost with your API host if needed
  static const String _baseUrl = 'http://192.168.1.7:5600';

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/login');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 8));

    if (resp.statusCode != 200) {
      return false;
    }

    final Map<String, dynamic> body = jsonDecode(resp.body);
    final token = body['token']?.toString();
    final profile = body['profile'] as Map<String, dynamic>?;

    if (token == null) {
      throw Exception('Login response missing token');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    if (profile != null) {
      await prefs.setString('profile_name', profile['name']?.toString() ?? '');
      await prefs.setString(
          'profile_email', profile['email']?.toString() ?? '');
      await prefs.setString(
          'profile_avatar', profile['avatar_url']?.toString() ?? '');
    }

    return true;
  }

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/signup');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body:
              jsonEncode({'email': email, 'password': password, 'name': name}),
        )
        .timeout(const Duration(seconds: 8));

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      try {
        final Map<String, dynamic> body = jsonDecode(resp.body);
        // normalize notice to a simple string under 'noticeText' for UI use
        if (body.containsKey('notice')) {
          body['noticeText'] = body['notice']?.toString();
        }
        if (body.containsKey('message')) {
          body['messageText'] = body['message']?.toString();
        }
        return body;
      } catch (_) {
        return {'status': 'ok'};
      }
    }

    String msg;
    try {
      final Map<String, dynamic> body = jsonDecode(resp.body);
      msg = (body['error'] ?? body['message'] ?? resp.reasonPhrase ?? resp.body)
          .toString();
    } catch (_) {
      msg = resp.body.isNotEmpty
          ? resp.body
          : 'Signup failed (status ${resp.statusCode})';
    }
    throw Exception(msg);
  }

  // Also update verifyEmail/resend to extract error messages safely:
  Future<bool> verifyEmail({
    required String email,
    required String code,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/verify');
    final resp = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'code': code}))
        .timeout(const Duration(seconds: 8));

    if (resp.statusCode == 200) return true;

    String msg;
    try {
      final Map<String, dynamic> body = jsonDecode(resp.body);
      msg = (body['error'] ?? body['message'] ?? resp.reasonPhrase ?? resp.body)
          .toString();
    } catch (_) {
      msg = resp.body.isNotEmpty
          ? resp.body
          : 'Verification failed (status ${resp.statusCode})';
    }
    throw Exception(msg);
  }

  Future<void> resendVerification({
    required String email,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/resend');
    final resp = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}))
        .timeout(const Duration(seconds: 8));

    if (resp.statusCode == 200) return;

    String msg;
    try {
      final Map<String, dynamic> body = jsonDecode(resp.body);
      msg = (body['error'] ?? body['message'] ?? resp.reasonPhrase ?? resp.body)
          .toString();
    } catch (_) {
      msg = resp.body.isNotEmpty
          ? resp.body
          : 'Resend failed (status ${resp.statusCode})';
    }
    throw Exception(msg);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('profile_name');
    await prefs.remove('profile_email');
    await prefs.remove('profile_avatar');
  }
}
