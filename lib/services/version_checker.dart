import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final bool updateAvailable;
  final String currentVersion;
  final String latestVersion;
  final String? updateUrl;

  UpdateInfo({
    required this.updateAvailable,
    required this.currentVersion,
    required this.latestVersion,
    this.updateUrl,
  });
}

class VersionChecker {
  // URL that returns JSON: {"latest":"1.2.3", "url":"https://..."}
  final String checkUrl;
  final Duration timeout;

  VersionChecker(
      {required this.checkUrl, this.timeout = const Duration(seconds: 6)});

  Future<UpdateInfo> check() async {
    final pkg = await PackageInfo.fromPlatform();
    final current = pkg.version;

    try {
      final resp = await http.get(Uri.parse(checkUrl)).timeout(timeout);
      if (resp.statusCode != 200) {
        return UpdateInfo(
            updateAvailable: false,
            currentVersion: current,
            latestVersion: current);
      }
      final Map<String, dynamic> jsonBody =
          json.decode(resp.body) as Map<String, dynamic>;
      final latest = (jsonBody['latest'] ?? current).toString();
      final url = jsonBody['url']?.toString();

      final available = _isVersionGreater(latest, current);

      return UpdateInfo(
        updateAvailable: available,
        currentVersion: current,
        latestVersion: latest,
        updateUrl: url,
      );
    } catch (_) {
      return UpdateInfo(
          updateAvailable: false,
          currentVersion: current,
          latestVersion: current);
    }
  }

  bool _isVersionGreater(String a, String b) {
    final aParts = a
        .split(RegExp(r'[^\d]+'))
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();
    final bParts = b
        .split(RegExp(r'[^\d]+'))
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();
    final len = (aParts.length > bParts.length) ? aParts.length : bParts.length;

    for (var i = 0; i < len; i++) {
      final ai = (i < aParts.length) ? aParts[i] : 0;
      final bi = (i < bParts.length) ? bParts[i] : 0;

      if (ai > bi) return true;
      if (ai < bi) return false;
    }
    return false;
  }
}
