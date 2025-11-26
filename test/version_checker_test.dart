import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:student_id_scanner/services/version_checker.dart';

void main() {
  test('reports update available when remote version is greater', () async {
    final mockClient = MockClient((req) async {
      final body = json.encode({
        'latest': '2.0.0',
        'url': 'https://example.com/app.apk',
      });
      return http.Response(body, 200);
    });

    final checker = VersionChecker(
      checkUrl: 'https://example.com/version.json',
      httpClient: mockClient,
      currentVersionOverride: '1.1.0',
    );

    final info = await checker.check();
    expect(info.updateAvailable, isTrue);
    expect(info.latestVersion, '2.0.0');
    expect(info.updateUrl, 'https://example.com/app.apk');
  });

  test('reports no update when versions equal', () async {
    final mockClient = MockClient((req) async {
      final body = json.encode({'latest': '1.1.0'});
      return http.Response(body, 200);
    });

    final checker = VersionChecker(
      checkUrl: 'https://example.com/version.json',
      httpClient: mockClient,
      currentVersionOverride: '1.1.0',
    );

    final info = await checker.check();
    expect(info.updateAvailable, isFalse);
    expect(info.latestVersion, '1.1.0');
  });

  test('handles non-200 response gracefully', () async {
    final mockClient = MockClient((req) async {
      return http.Response('Not found', 404);
    });

    final checker = VersionChecker(
      checkUrl: 'https://example.com/version.json',
      httpClient: mockClient,
      currentVersionOverride: '1.1.0',
    );

    final info = await checker.check();
    expect(info.updateAvailable, isFalse);
    expect(info.latestVersion, '1.1.0');
  });
}
