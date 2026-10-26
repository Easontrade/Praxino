import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/enhance/enhance_pack.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('praxino-pack-');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  EnhancePackManifest manifestFor(List<int> bytes, {String? hash}) =>
      EnhancePackManifest(
        version: '1',
        url: 'https://example.test/libmpv-2.dll',
        sha256: hash ?? sha256Hex(bytes),
      );

  test('downloads, verifies and reports the installed file', () async {
    final bytes = utf8.encode('fake libmpv');
    final downloader = EnhancePackDownloader(
      root: temp.path,
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/libmpv-2.dll');
        return http.Response.bytes(bytes, 200);
      }),
    );

    final file = await downloader.download(manifestFor(bytes));
    expect(await file.readAsBytes(), bytes);
    expect(await downloader.isInstalled(manifestFor(bytes)), isTrue);
    downloader.close();
  });

  test('rejects a mismatched hash and leaves no file', () async {
    final downloader = EnhancePackDownloader(
      root: temp.path,
      client: MockClient((_) async => http.Response('bad', 200)),
    );

    expect(
      () => downloader.download(manifestFor(utf8.encode('good'))),
      throwsA(isA<EnhancePackException>()),
    );
    expect(
      File('${temp.path}${Platform.pathSeparator}libmpv-2.dll').existsSync(),
      isFalse,
    );
    downloader.close();
  });

  test('rejects HTTP failures', () async {
    final downloader = EnhancePackDownloader(
      root: temp.path,
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    expect(
      () => downloader.download(manifestFor(utf8.encode('x'))),
      throwsA(isA<EnhancePackException>()),
    );
    downloader.close();
  });

  test('manifest json validates required fields', () {
    final manifest = manifestFor(utf8.encode('x'));
    final restored =
        EnhancePackManifest.tryFromJson(jsonDecode(encodeManifest(manifest)));
    expect(restored!.sha256, manifest.sha256);

    expect(EnhancePackManifest.tryFromJson({'version': '1'}), isNull);
  });
}
