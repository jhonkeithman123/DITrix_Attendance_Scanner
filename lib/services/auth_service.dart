// ...existing code...
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Replace localhost with your API host if needed
  static const String _baseUrl = 'http://localhost:5600';

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

  Future<bool> signUp({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/signup');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 8));
    return resp.statusCode == 200 || resp.statusCode == 201;
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('profile_name');
    await prefs.remove('profile_email');
    await prefs.remove('profile_avatar');
  }
}
