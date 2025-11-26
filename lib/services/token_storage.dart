import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class TokenStorage {
  static const _dirName = 'cache';
  static const _fileName = 'auth.json';

  static Future<Directory> _appDir() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _file() async {
    final dir = await _appDir();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> saveToken(String token, {int? expiresAtEpochMs}) async {
    final f = await _file();
    final Map<String, dynamic> obj = {
      'token': token,
      if (expiresAtEpochMs != null) 'expiresAt': expiresAtEpochMs,
      'saveAt': DateTime.now().toIso8601String(),
    };
    await f.writeAsString(jsonEncode(obj));
  }

  static Future<String?> getToken() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final txt = await f.readAsString();
      final Map<String, dynamic> obj = jsonDecode(txt);
      final t = obj['token'];
      if (t is String && t.isNotEmpty) return t;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteToken() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> readAll() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final txt = await f.readAsString();
      return Map<String, dynamic>.from(jsonDecode(txt));
    } catch (_) {
      return null;
    }
  }
}
