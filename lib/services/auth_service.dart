import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/token_storage.dart';

class AuthService {
  // BaseUrl via constructor so it's easy to override for emulator / prod
  final String _baseUrl;
  // ignore: unused_field
  final String _globalUrl =
      "https://ditrix-attendance-scanner-server.onrender.com";
  // ignore: unused_field
  final String _localUrl = "http://10.0.2.2:5600";

  AuthService(
      {String? baseUrl =
          "https://ditrix-attendance-scanner-server.onrender.com"})
      : _baseUrl = baseUrl ??
            // default to local dev IP; for Android emulator use 10.0.2.2'
            "http://localhost:5600";

  // Helper to fetch the firebase id token
  Future<String?> _getFirebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  // Rest API with authentiacation
  Future<http.Response> _authedPost(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 120)}) async {
    final idToken = await _getFirebaseIdToken();
    if (idToken == null) throw Exception("Not authenticated");

    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
    try {
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
      _checkServiceUnavailable(resp);
      return resp;
    } on TimeoutException {
      throw Exception('Request timed out. Is the server running at $_baseUrl?');
    } on SocketException {
      throw Exception('Network error. Unable to reach server at $_baseUrl');
    }
  }

  Future<http.Response> _authedPut(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 120)}) async {
    final idToken = await _getFirebaseIdToken();
    if (idToken == null) throw Exception("Not authenticated");

    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
    try {
      final resp = await http
          .put(uri, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
      _checkServiceUnavailable(resp);
      return resp;
    } on TimeoutException {
      throw Exception('Request timed out. Is the server running at $_baseUrl?');
    } on SocketException {
      throw Exception('Network error. Unable to reach server at $_baseUrl');
    }
  }

  // ignore: unused_element
  Future<http.Response> _authedPatch(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 120)}) async {
    final idToken = await _getFirebaseIdToken();
    if (idToken == null) throw Exception("Not authenticated");

    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
    try {
      final resp = await http
          .patch(uri, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
      _checkServiceUnavailable(resp);
      return resp;
    } on TimeoutException {
      throw Exception('Request timed out. Is the server running at $_baseUrl?');
    } on SocketException {
      throw Exception('Network error. Unable to reach server at $_baseUrl');
    }
  }

  // helper to POST JSON with timeout and clearer errors
  Future<http.Response> _postJson(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 120)}) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final resp = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(timeout);
      _checkServiceUnavailable(resp);
      return resp;
    } on TimeoutException {
      throw Exception('Request timed out. Is the server running at $_baseUrl?');
    } on SocketException {
      throw Exception('Network error. Unable to reach server at $_baseUrl');
    }
  }

  Future<http.Response> _patchJson(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 120)}) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final resp = await http
          .patch(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(timeout);
      _checkServiceUnavailable(resp);
      return resp;
    } on TimeoutException {
      throw Exception('Request timed out. Is the server running at $_baseUrl?');
    } on SocketException {
      throw Exception('Network error. Unable to reach server at $_baseUrl');
    }
  }

  void _checkServiceUnavailable(http.Response resp) {
    if (resp.statusCode == 503) {
      throw Exception(
          'Server temporarily unavailable (DB down). Try again later.');
    }
  }

  /// Validate existing client token against server session store.
  /// Returns profile map on success, null otherwise.
  Future<Map<String, dynamic>?> validateSession() async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    print(
        '[AuthService] validateSession token(head)=${token != null ? '${token.substring(0, 12)}...' : '(none)'}');
    if (token == null) return null;

    final uri = Uri.parse('$_baseUrl/auth/session');
    try {
      final resp = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 120));

      print('[AuthService] /auth/session status=${resp.statusCode}');
      if (resp.body.isNotEmpty) {
        try {
          print('[AuthService] /auth/session body=${resp.body}');
        } catch (_) {}
      }

      if (resp.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(resp.body);
        return body['profile'] is Map
            ? Map<String, dynamic>.from(body['profile'])
            : null;
      }

      return null;
    } on TimeoutException {
      throw Exception('Request timed out. Is the server running at $_baseUrl?');
    } on SocketException {
      throw Exception('Network error. Unable to reach server at $_baseUrl');
    } catch (_) {
      return null;
    }
  }

  // update usages that call URIs without base (they already mostly use $_baseUrl)
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // Sign in with Firebase Auth
      final userCred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final idToken = await userCred.user?.getIdToken();
      if (idToken == null) {
        throw Exception('Failed to obtain Firebase ID token');
      }

      // persist token
      await TokenStorage.saveToken(idToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', idToken);

      // fetch profile from server using ID token
      final uri = Uri.parse('$_baseUrl/auth/session');
      final resp = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      }).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        // non-fatal: still signed into Firebase, but server-side profile missing
        return true;
      }

      final Map<String, dynamic> body = jsonDecode(resp.body);
      final profile = body['profile'] is Map
          ? Map<String, dynamic>.from(body['profile'])
          : null;
      if (profile != null) {
        await prefs.setString(
            'profile_name', profile['name']?.toString() ?? '');
        await prefs.setString(
            'profile_email', profile['email']?.toString() ?? '');
        await prefs.setString(
            'profile_avatar', profile['avatar_url']?.toString() ?? '');
      }
      return true;
    } on FirebaseAuthException catch (e, st) {
      print(
          '[AuthService] FireBaseAuthException code=${e.code} message=${e.message}');
      print(st);
      rethrow;
    } catch (e, st) {
      print('[AuthService] signIn unknown error: $e');
      print(st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    await TokenStorage.deleteToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profile_name');
    await prefs.remove('profile_email');
    await prefs.remove('profile_avatar');
  }

  Future<void> logout() async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    try {
      if (token != null) {
        final uri = Uri.parse("$_baseUrl/auth/logout");
        final response = await http.post(uri, headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        }).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          print('Server logout returned ${response.statusCode}');
        }
      }
    } finally {
      await FirebaseAuth.instance.signOut();
      await TokenStorage.deleteToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    }
  }

  /// Ask server to extend the current session expiry.
  /// Returns ISO expiry string on success, null on failure.
  Future<String?> refreshSession() async {
    String? token = await _getFirebaseIdToken();
    token ??= await TokenStorage.getToken();
    if (token == null) return null;

    final uri = Uri.parse("$_baseUrl/auth/refresh");

    try {
      final resp = await http.post(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      return body['expiresAt'] as String?;
    } on Exception catch (e) {
      print('refreshSession failed: $e');
      return null;
    }
  }

  /// Upload avatar image file (multipart/form-data PUT /profile)
  Future<Map<String, dynamic>> uploadProfileAvatar(File imageFile,
      {String? name}) async {
    final idToken = await _getFirebaseIdToken();
    if (idToken == null) throw Exception("Not authenticated");
    ;

    final uri = Uri.parse('$_baseUrl/profile');
    final req = http.MultipartRequest('PUT', uri);
    req.headers['Authorization'] = 'Bearer $idToken';
    // attach optional name as field
    if (name != null) req.fields['name'] = name;

    final mimeType = lookupMimeType(imageFile.path) ?? 'image/jpeg';
    final parts = mimeType.split('/');
    req.files.add(await http.MultipartFile.fromPath(
      'avatar',
      imageFile.path,
      contentType: MediaType(parts[0], parts[1]),
    ));

    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      String msg = resp.body.isNotEmpty ? resp.body : 'Upload failed';
      try {
        final parsed = jsonDecode(resp.body);
        msg = (parsed['error'] ?? parsed['message'] ?? msg).toString();
      } catch (_) {}
      throw Exception('Avatar upload failed: ${resp.statusCode} - $msg');
    }
    final Map<String, dynamic> body = jsonDecode(resp.body);
    return body;
  }

// helper to get mime type
  String? lookupMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  /// upload local capture sessions to server
  Future<int> uploadCaptures(List<Map<String, dynamic>> captures) async {
    final resp = await _authedPost('/sync/captures', {'captures': captures});

    if (resp.statusCode != 200) {
      // Try to extract a helpful message from the server response
      String serverMsg = resp.body;
      try {
        final Map<String, dynamic> parsed = jsonDecode(resp.body);
        serverMsg =
            (parsed['error'] ?? parsed['message'] ?? serverMsg).toString();
      } catch (_) {}
      throw Exception('Upload failed: ${resp.statusCode} - $serverMsg');
    }

    final body = jsonDecode(resp.body);
    return (body['uploaded'] is int) ? body['uploaded'] as int : 0;
  }

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    // POST to signup (was incorrectly using /auth/login)
    final resp = await _postJson(
        '/auth/signup', {'email': email, 'password': password, 'name': name});

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      try {
        final Map<String, dynamic> body = jsonDecode(resp.body);
        if (body.containsKey('notice')) {
          body['noticeText'] = body['notice']?.toString();
        }
        if (body.containsKey('message')) {
          body['messageText'] = body['message']?.toString();
        }
        await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
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
    final resp =
        await _postJson('/auth/verify', {'email': email, 'code': code});

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
    final resp = await _postJson('/auth/resend', {'email': email});

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

  Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    final resp = await _postJson('/auth/forgot', {'email': email});

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      try {
        final Map<String, dynamic> body = jsonDecode(resp.body);
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
          : 'Request failed (status ${resp.statusCode})';
    }
    throw Exception(msg);
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final resp = await _patchJson('/auth/reset',
        {'email': email, 'code': code, 'newPassword': newPassword});

    if (resp.statusCode == 200 || resp.statusCode == 201) return;

    String msg;
    try {
      final Map<String, dynamic> body = jsonDecode(resp.body);
      msg = (body['error'] ?? body['message'] ?? resp.reasonPhrase ?? resp.body)
          .toString();
    } catch (_) {
      msg = resp.body.isNotEmpty
          ? resp.body
          : 'Reset failed (status ${resp.statusCode})';
    }
    throw Exception(msg);
  }

  Future<void> updateProfile(
      {required String name, String? avatarBase64}) async {
    final body = <String, dynamic>{'name': name};
    if (avatarBase64 != null) body['avatarBase64'] = avatarBase64;

    final resp = await _authedPut('/profile', body);

    if (resp.statusCode != 200) {
      final msg = resp.body.isNotEmpty ? resp.body : 'Server error';
      throw Exception('Failed to update profile: $msg');
    }
    return;
  }
}
