import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/danmaku/dandanplay_provider.dart';
import 'package:praxino/core/danmaku/danmaku_engine.dart';
import 'package:praxino/core/danmaku/danmaku_file_hash.dart';
import 'package:praxino/core/danmaku/danmaku_match_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  test('match signs the path and parses the first match', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v2/match');
      expect(request.headers['X-AppId'], 'id');
      expect(request.headers['X-Timestamp'], '1700000000');
      final expected = base64Encode(
        sha256.convert(utf8.encode('id1700000000/api/v2/matchsecret')).bytes,
      );
      expect(request.headers['X-Signature'], expected);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['fileName'], 'demo.mkv');
      expect(body['fileSize'], 123);
      return _json({
        'success': true,
        'isMatched': true,
        'matches': [
          {'episodeId': 42, 'animeTitle': 'Demo', 'episodeTitle': 'E1'}
        ]
      });
    });

    final api = DandanplayClient(
      appId: 'id',
      appSecret: 'secret',
      client: client,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );

    final match = await api.match(
      fileName: 'demo.mkv',
      fileHash: 'hash',
      fileSize: 123,
    );
    expect(match!.episodeId, 42);
    expect(match.episodeTitle, 'E1');
  });

  test('comments decode time, mode and RGB color', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v2/comment/42');
      expect(request.url.queryParameters['withRelated'], 'true');
      return _json({
        'success': true,
        'comments': [
          {'p': '1.5,1,16777215,uid', 'm': '滚动'},
          {'p': '2,5,255', 'm': '顶部'},
          {'p': '3,4,0', 'm': '底部'},
          {'p': 'bad', 'm': 'skip'},
        ],
      });
    });
    final api = DandanplayClient(appId: 'id', appSecret: 'secret', client: client);

    final comments = await api.comments(42);
    expect(comments, hasLength(3));
    expect(comments[0].time, const Duration(milliseconds: 1500));
    expect(comments[0].mode, DanmakuMode.scroll);
    expect(comments[0].color, 0xFFFFFFFF);
    expect(comments[1].mode, DanmakuMode.top);
    expect(comments[1].color, 0xFF0000FF);
    expect(comments[2].mode, DanmakuMode.bottom);
  });

  test('searchEpisodes parses episode ids', () async {
    final api = DandanplayClient(
      appId: 'id',
      appSecret: 'secret',
      client: MockClient((request) async {
        expect(request.url.queryParameters['anime'], 'Demo');
        return _json({
          'success': true,
          'episodes': [
            {'episodeId': 7, 'animeTitle': 'Demo', 'episodeTitle': 'E1'}
          ]
        });
      }),
    );

    final episodes = await api.searchEpisodes(anime: 'Demo', episode: '1');
    expect(episodes.single.episodeId, 7);
  });

  test('API errors become DandanplayException', () async {
    final api = DandanplayClient(
      appId: 'id',
      appSecret: 'secret',
      client: MockClient((_) async => _json({
            'success': false,
            'errorMessage': 'bad app',
          })),
    );
    expect(() => api.searchEpisodes(anime: 'x'),
        throwsA(isA<DandanplayException>()));
  });

  test('file hash is MD5 of the first 16 MiB', () async {
    final temp = Directory.systemTemp.createTempSync('praxino-hash-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}${Platform.pathSeparator}video.bin');
    final bytes = utf8.encode('hello danmaku');
    file.writeAsBytesSync(bytes);

    expect(await DanmakuFileHash.of(file), md5.convert(bytes).toString());
  });

  test('match store remembers per show', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DanmakuMatchStore(await SharedPreferences.getInstance());
    expect(store.episodeFor('demo-E1'), isNull);
    await store.remember('demo-E1', 42);
    expect(store.episodeFor('demo-E1'), 42);
    await store.forget('demo-E1');
    expect(store.episodeFor('demo-E1'), isNull);
  });
}
