import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

int _compareVersionParts(String a, String b) {
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
    if (ai > bi) return 1;
    if (ai < bi) return -1;
  }
  return 0;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
        'Usage: dart run tool/check_version_cli.dart <check_url> [current_version]');
    exit(2);
  }

  final url = args[0];
  final currentVersion = args.length > 1 ? args[1] : '0.0.0';

  try {
    final resp =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      stderr.writeln('HTTP ${resp.statusCode}: ${resp.reasonPhrase}');
      exit(3);
    }

    final Map<String, dynamic> body =
        json.decode(resp.body) as Map<String, dynamic>;
    // support both keys: "latest_version" or "latest"
    final latest =
        (body['latest_version'] ?? body['latest'] ?? currentVersion).toString();
    // support either "update_urls" map or single "url"
    final updateUrl = (body['update_urls'] is Map)
        ? (body['update_urls'] as Map).values.first.toString()
        : (body['url']?.toString());

    final cmp = _compareVersionParts(latest, currentVersion);
    final available = cmp > 0;

    final out = {
      'checkUrl': url,
      'currentVersion': currentVersion,
      'latestVersion': latest,
      'updateAvailable': available,
      'updateUrl': updateUrl,
    };
    stdout.writeln(JsonEncoder.withIndent('  ').convert(out));
    exit(0);
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}
