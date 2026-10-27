import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:praxino/core/enhance/enhance_pack_bundle.dart';

Uint8List _zip(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

EnhancePackFile _file(
  String name,
  String path,
  List<int> bytes, {
  bool archive = false,
  String? extractTo,
  int strip = 0,
}) =>
    EnhancePackFile(
      name: name,
      url: 'https://example.test/$path',
      sha256: _sha(bytes),
      fileName: archive ? 'archive.zip' : path,
      license: 'MIT',
      archive: archive,
      extractTo: extractTo,
      stripComponents: strip,
    );

void main() {
  late Directory temp;
  late List<EnhancePackFile> files;
  late Map<String, List<int>> responses;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('praxino-pack-');
    final libmpv = <int>[1, 2, 3, 4];
    final pythonZip = _zip({
      'python312.dll': [5, 6, 7],
      'python.exe': [8, 9],
      'Lib/site-packages/vapoursynth/vsscript.dll': [10],
      'Lib/site-packages/vapoursynth/vapoursynth.pyd': [11],
    });
    final models = _zip({
      'rife-v4.6/flownet.bin': [12, 13],
      'rife-v4.6/README.md': [14],
    });
    files = [
      _file('libmpv', 'libmpv-2.dll', libmpv),
      _file(
        '便携 Python',
        'python.zip',
        pythonZip,
        archive: true,
        extractTo: 'python',
      ),
      _file(
        'RIFE 模型',
        'models.zip',
        models,
        archive: true,
        extractTo:
            'python/Lib/site-packages/vapoursynth/plugins/models',
      ),
    ];
    responses = {
      '/libmpv-2.dll': libmpv,
      '/python.zip': pythonZip,
      '/models.zip': models,
    };
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  http.Client clientFor(Map<String, List<int>> byPath) => MockClient((request) async {
        final body = byPath[request.url.path];
        if (body == null) return http.Response('missing', 404);
        return http.Response.bytes(body, 200);
      });

  test('parses a multi-file bundle', () {
    final json = {
      'version': 'r81-test',
      'name': '测试增强包',
      'files': files.map((file) => file.toJson()).toList(),
    };
    final bundle = EnhancePackBundle.tryFromJson(json);
    expect(bundle, isNotNull);
    expect(bundle!.version, 'r81-test');
    expect(bundle.files, hasLength(3));
    expect(bundle.files[0].license, 'MIT');
    expect(bundle.files[1].archive, isTrue);
  });

  test('rejects a manifest that does not document licenses', () {
    final json = {
      'version': '1',
      'files': [
        {
          'name': 'libmpv',
          'url': 'https://example.test/libmpv-2.dll',
          'sha256': 'a' * 64,
          'fileName': 'libmpv-2.dll',
          'license': '  ',
        },
      ],
    };
    expect(EnhancePackBundle.tryFromJson(json), isNull);
  });

  test('installs every file, verifies hashes and finds the runtime', () async {
    final bundle = EnhancePackBundle(version: '1', files: files);
    final installer = EnhancePackInstaller(
      root: temp.path,
      client: clientFor(responses),
    );
    final result = await installer.install(bundle);
    installer.close();

    expect(
      File(p.join(temp.path, 'libmpv-2.dll')).readAsBytesSync(),
      [1, 2, 3, 4],
    );
    expect(File(p.join(temp.path, 'python', 'python312.dll')).existsSync(),
        isTrue);
    final site = p.join(
      temp.path,
      'python',
      'Lib',
      'site-packages',
      'vapoursynth',
    );
    expect(File(p.join(site, 'vsscript.dll')).existsSync(), isTrue);
    expect(
      File(p.join(site, 'plugins', 'models', 'rife-v4.6', 'flownet.bin'))
          .existsSync(),
      isTrue,
    );
    expect(result.libmpvPath, p.join(temp.path, 'libmpv-2.dll'));
    expect(result.hasVapourSynth, isTrue);
    expect(p.equals(result.pythonDir!, p.join(temp.path, 'python')), isTrue);
    expect(p.equals(result.siteDir!, site), isTrue);
    expect(Directory(p.join(temp.path, '.downloads')).existsSync(), isFalse);
  });

  test('a bad hash aborts without writing the target file', () async {
    final broken = EnhancePackFile(
      name: 'libmpv',
      url: 'https://example.test/libmpv-2.dll',
      sha256: 'b' * 64,
      fileName: 'libmpv-2.dll',
      license: 'GPL-2.0',
    );
    final installer = EnhancePackInstaller(
      root: temp.path,
      client: clientFor(responses),
    );
    await expectLater(
      installer.install(EnhancePackBundle(version: '1', files: [broken])),
      throwsA(isA<EnhancePackBundleException>()),
    );
    installer.close();
    expect(File(p.join(temp.path, 'libmpv-2.dll')).existsSync(), isFalse);
    expect(Directory(p.join(temp.path, '.downloads')).existsSync(), isFalse);
  });

  test('rejects archive entries that escape the destination', () async {
    final evil = _zip({'../evil.txt': [1, 2, 3]});
    final entry = _file('evil', 'evil.zip', evil, archive: true, extractTo: 'x');
    final installer = EnhancePackInstaller(
      root: temp.path,
      client: clientFor({'/evil.zip': evil}),
    );
    await expectLater(
      installer.install(EnhancePackBundle(version: '1', files: [entry])),
      throwsA(isA<EnhancePackBundleException>()),
    );
    installer.close();
    expect(File(p.join(temp.path, 'evil.txt')).existsSync(), isFalse);
  });

  test('stripComponents drops the release folder wrapper', () async {
    final wrapped = _zip({'v1/bin/tool.dll': [1, 2]});
    final entry = EnhancePackFile(
      name: 'tool',
      url: 'https://example.test/tool.zip',
      sha256: _sha(wrapped),
      fileName: 'tool.zip',
      license: 'MIT',
      archive: true,
      extractTo: 'tool',
      stripComponents: 1,
    );
    final installer = EnhancePackInstaller(
      root: temp.path,
      client: clientFor({'/tool.zip': wrapped}),
    );
    await installer.install(EnhancePackBundle(version: '1', files: [entry]));
    installer.close();
    expect(File(p.join(temp.path, 'tool', 'bin', 'tool.dll')).existsSync(),
        isTrue);
  });

  test('fetches and parses a manifest URL', () async {
    final json = {
      'version': '1',
      'files': files.map((file) => file.toJson()).toList(),
    };
    final installer = EnhancePackInstaller(
      root: temp.path,
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/manifest.json');
        return http.Response.bytes(
          utf8.encode(jsonEncode(json)),
          200,
        );
      }),
    );
    final decoded =
        await installer.fetchManifest('https://example.test/manifest.json');
    final bundle = EnhancePackBundle.tryFromJson(decoded);
    expect(bundle, isNotNull);
    expect(bundle!.files, hasLength(3));
    installer.close();
  });
}
