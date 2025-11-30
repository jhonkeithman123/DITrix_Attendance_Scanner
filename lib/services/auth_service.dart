import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/token_storage.dart';

class AuthService {
  // BaseUrl via constructor so it's easy to override for emulator / prod
  final String _baseUrl;

  AuthService({String? baseUrl})
      : _baseUrl = baseUrl ??
            // default to local dev IP; for Android emulator use 10.0.2.2'
            'http://localhost:5600';

  // helper to POST JSON with timeout and clearer errors
  Future<http.Response> _postJson(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 10)}) async {
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

  Future<http.Response> _authedPost(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final token = await TokenStorage.getToken();
    if (token == null) throw Exception("Not authenticated");

    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
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
      {Duration timeout = const Duration(seconds: 10)}) async {
    final token = await TokenStorage.getToken();
    if (token == null) throw Exception("Not authenticated");

    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
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
      {Duration timeout = const Duration(seconds: 10)}) async {
    final token = await TokenStorage.getToken();
    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
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

  Future<http.Response> _patchJson(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 8)}) async {
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
    final token = await TokenStorage.getToken();
    if (token == null) return null;

    final uri = Uri.parse('/auth/session');
    try {
      final resp = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 8));

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
    final resp =
        await _postJson('/auth/login', {'email': email, 'password': password});

    if (resp.statusCode != 200) {
      String msg;
      try {
        final Map<String, dynamic> body = jsonDecode(resp.body);
        msg =
            (body['error'] ?? body['message'] ?? resp.reasonPhrase ?? resp.body)
                .toString();
      } catch (_) {
        msg = resp.body.isNotEmpty
            ? resp.body
            : 'Sign in failed (status ${resp.statusCode})';
      }
      throw Exception(msg);
    }

    final Map<String, dynamic> body = jsonDecode(resp.body);
    final token = body['token']?.toString();
    if (token == null) throw Exception('Login response missing token');

    final profile = (body['profile'] is Map)
        ? Map<String, dynamic>.from(body['profile'])
        : null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    // also save token to file cache used by TokenStorage.getToken()
    await TokenStorage.saveToken(token);
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
    final resp = await _postJson(
        '/auth/login', {'email': email, 'password': password, 'name': name});

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

  /// upload local capture sessions to server
  Future<int> uploadCaptures(List<Map<String, dynamic>> captures) async {
    final resp = await _authedPost('/sync/captures', {'captures': captures});

    if (resp.statusCode != 200) {
      throw Exception('Upload failed: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    return (body['uploaded'] is int) ? body['uploaded'] as int : 0;
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('profile_name');
    await prefs.remove('profile_email');
    await prefs.remove('profile_avatar');
  }

  /// Ask server to extend the current session expiry.
  /// Returns ISO expiry string on success, null on failure.
  Future<String?> refreshSession() async {
    final token = await TokenStorage.getToken();
    if (token == null) return null;
    final uri = Uri.parse('$_baseUrl/auth/refresh');
    try {
      final resp = await http.post(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      return body['expiresAt'] as String?;
    } on Exception catch (e) {
      print('refreshSession failed: $e');
      return null;
    }
  }
}
