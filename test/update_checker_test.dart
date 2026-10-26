import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/update/update_checker.dart';

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  test('reports a newer release', () async {
    final checker = UpdateChecker(
      currentVersion: '1.0.0',
      client: MockClient((request) async {
        expect(request.url.path, '/repos/Easontrade/Praxino/releases/latest');
        return _json({
          'tag_name': 'v1.2.0',
          'html_url': 'https://github.com/Easontrade/Praxino/releases/tag/v1.2.0',
          'body': 'notes',
        });
      }),
    );
    final info = await checker.check();
    expect(info!.version, '1.2.0');
    expect(info.notes, 'notes');
    checker.close();
  });

  test('ignores the same, older and skipped versions', () async {
    for (final tag in ['v1.0.0', 'v0.9.0']) {
      final checker = UpdateChecker(
        currentVersion: '1.0.0',
        client: MockClient((_) async => _json({'tag_name': tag})),
      );
      expect(await checker.check(), isNull);
      checker.close();
    }

    final skipped = UpdateChecker(
      currentVersion: '1.0.0',
      skippedVersion: '1.2.0',
      client: MockClient((_) async => _json({'tag_name': 'v1.2.0'})),
    );
    expect(await skipped.check(), isNull);
    skipped.close();
  });

  test('network errors are silent', () async {
    final checker = UpdateChecker(
      currentVersion: '1.0.0',
      client: MockClient((_) async => http.Response('down', 500)),
    );
    expect(await checker.check(), isNull);
    checker.close();
  });

  test('compares numeric versions', () {
    expect(UpdateChecker.compareVersions('1.2.0', '1.1.9'), greaterThan(0));
    expect(UpdateChecker.compareVersions('1.0', '1.0.0'), 0);
    expect(UpdateChecker.compareVersions('v1.0.1', '1.0.0'), greaterThan(0));
  });
}
