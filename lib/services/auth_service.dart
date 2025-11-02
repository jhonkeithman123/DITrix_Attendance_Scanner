import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Replace localhost with your API host if needed
  static const String _baseUrl = 'http://192.168.1.3:5600';

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
      return resp;
    } on TimeoutException {
      throw Exception('Request timed out. Is the server running at $_baseUrl?');
    } on SocketException {
      throw Exception('Network error. Unable to reach server at $_baseUrl');
    }
  }

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
    final profile = (body['profile'] is Map)
        ? Map<String, dynamic>.from(body['profile'])
        : null;

    if (token == null) throw Exception('Login response missing token');

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

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('profile_name');
    await prefs.remove('profile_email');
    await prefs.remove('profile_avatar');
  }
}
