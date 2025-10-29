import 'dart:convert';
import 'dart:io';
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
  final http.Client _httpClient;
  final String? _currentVersionOverride;

  VersionChecker({
    required this.checkUrl,
    this.timeout = const Duration(seconds: 6),
    http.Client? httpClient,
    String? currentVersionOverride,
  })  : _httpClient = httpClient ?? http.Client(),
        _currentVersionOverride = currentVersionOverride;

  Future<UpdateInfo> check() async {
    // Order of precedence for current version:
    // 1) constructor currentVersionOverride
    // 2) environment variable VERSION_OVERRIDE (useful for CLI/tests)
    // 3) package info from the running app
    final envOverride = Platform.environment['VERSION_OVERRIDE'];
    final current = _currentVersionOverride ??
        envOverride ??
        (await PackageInfo.fromPlatform()).version;

    try {
      final resp = await _httpClient.get(Uri.parse(checkUrl)).timeout(timeout);
      if (resp.statusCode != 200) {
        return UpdateInfo(
            updateAvailable: false,
            currentVersion: current,
            latestVersion: current);
      }
      final Map<String, dynamic> jsonBody =
          json.decode(resp.body) as Map<String, dynamic>;
      // support both "latest" and "latest_version" keys, and "url" or "update_urls" map
      final latest =
          (jsonBody['latest'] ?? jsonBody['latest_version'] ?? current)
              .toString();
      String? url;
      if (jsonBody['url'] != null) {
        url = jsonBody['url'].toString();
      } else if (jsonBody['update_urls'] is Map) {
        final m = Map<String, dynamic>.from(jsonBody['update_urls'] as Map);
        if (m.isNotEmpty) url = m.values.first.toString();
      }

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
