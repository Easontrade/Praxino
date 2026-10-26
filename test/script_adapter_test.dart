import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/sources/script/quickjs_host.dart';
import 'package:praxino/core/sources/script/script_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsReady = Platform.isWindows &&
      (Platform.environment['FLUTTER_QJS_NEXT_LIBRARY'] != null ||
          File('flutter_qjs_next_plugin.dll').existsSync());
  final skip = quickJsReady ? null : 'QuickJS plugin DLL not available';
  void quickTest(String description, Future<void> Function() body) =>
      test(description, body, skip: skip);

  quickTest('runs pure JS and parses JSON', () async {
    final host = QuickJsHost(timeout: const Duration(seconds: 2));
    expect(await host.runJson('1 + 1'), 2);
    expect(await host.runJson('JSON.stringify({a: 1})'), {'a': 1});
    host.close();
  });

  quickTest('does not expose file, process or module globals', () async {
    final host = QuickJsHost(timeout: const Duration(seconds: 2));
    final result = await host.runJson(
      'typeof require + "|" + typeof process + "|" + typeof std + "|" + typeof os',
    );
    expect(result, 'undefined|undefined|undefined|undefined');
    host.close();
  });

  quickTest('fetch is backed by the injected http client', () async {
    final host = QuickJsHost(
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/api');
        return http.Response('hello', 200);
      }),
      timeout: const Duration(seconds: 2),
    );
    final result = await host.runJson('''
      (async () => {
        const response = await fetch('https://example.test/api');
        return JSON.stringify({text: await response.text(), status: response.status});
      })()
    ''');
    expect(result, {'text': 'hello', 'status': 200});
    host.close();
  });

  quickTest('interrupts a runaway script', () async {
    final host = QuickJsHost(timeout: const Duration(milliseconds: 100));
    await expectLater(
      host.runJson('while (true) {}'),
      throwsA(isA<QuickJsException>()),
    );
    host.close();
  });

  quickTest('enforces the heap limit', () async {
    final host = QuickJsHost(
      timeout: const Duration(seconds: 2),
      memoryLimit: 1024 * 1024,
    );
    await expectLater(
      host.runJson('new Array(100000000).fill(1)'),
      throwsA(isA<QuickJsException>()),
    );
    host.close();
  });

  quickTest('script adapter maps search, episodes and resolve', () async {
    final adapter = ScriptAdapter(
      id: 'script:demo',
      name: 'Demo Script',
      script: '''
function search(keyword) {
  return [{title: 'Demo ' + keyword, url: 'demo-1'}];
}
function episodes(media) {
  return [{name: '线路', episodes: [{name: '第1集', url: 'ep-1'}]}];
}
async function resolve(episode) {
  return {url: 'https://example.test/v.mp4', height: 720, headers: {Referer: 'x'}};
}
''',
    );
    expect(adapter.hash, hasLength(64));
    final hits = await adapter.search('test');
    expect(hits.single.title, 'Demo test');
    final groups = await adapter.episodes(hits.single);
    expect(groups.single.episodes.single.url, 'ep-1');
    final stream = await adapter.resolve(groups.single.episodes.single);
    expect(stream!.url, 'https://example.test/v.mp4');
    expect(stream.height, 720);
    expect(stream.headers['Referer'], 'x');
    adapter.close();
  });
}
