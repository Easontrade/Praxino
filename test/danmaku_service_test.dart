import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/danmaku/danmaku_service.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  test('matches a local file and reuses the remembered episode', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    await settings.setDandanplayCredentials('id', 'secret');

    final temp = Directory.systemTemp.createTempSync('praxino-danmaku-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final video = File('${temp.path}${Platform.pathSeparator}Demo - 01.mkv')
      ..writeAsBytesSync(List.filled(32, 1));

    var matchCalls = 0;
    var commentCalls = 0;
    final service = DanmakuService(
      settings: settings,
      client: MockClient((request) async {
        if (request.url.path == '/api/v2/match') {
          matchCalls++;
          return _json({
            'success': true,
            'isMatched': true,
            'matches': [
              {'episodeId': 42, 'animeTitle': 'Demo', 'episodeTitle': 'E1'}
            ]
          });
        }
        if (request.url.path == '/api/v2/comment/42') {
          commentCalls++;
          return _json({
            'success': true,
            'comments': [
              {'p': '1,1,16777215', 'm': 'hello'}
            ]
          });
        }
        return http.Response('not found', 404);
      }),
    );

    final first = await service.forLocalFile(video.path);
    expect(first, hasLength(1));
    expect(first!.single.text, 'hello');
    expect(matchCalls, 1);
    expect(commentCalls, 1);

    final second = await service.forLocalFile(video.path);
    expect(second, hasLength(1));
    expect(matchCalls, 1, reason: 'remembered episode should skip match');
    expect(commentCalls, 2);
    service.close();
  });

  test('missing credentials or files return null', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final service = DanmakuService(settings: settings);
    expect(await service.forLocalFile('missing.mkv'), isNull);
    service.close();
  });
}
