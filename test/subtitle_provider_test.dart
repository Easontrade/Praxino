import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/subtitles/assrt_provider.dart';
import 'package:praxino/core/subtitles/opensubtitles_provider.dart';
import 'package:praxino/core/subtitles/subtitle_provider.dart';
import 'package:praxino/core/subtitles/subtitle_store.dart';

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  test('OpenSubtitles searches and downloads through the link', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/subtitles') {
        expect(request.headers['Api-Key'], 'key');
        expect(request.url.queryParameters['season_number'], '1');
        return _json({
          'data': [
            {
              'id': '9',
              'attributes': {
                'language': 'zh-cn',
                'download_count': 12,
                'release': 'Demo S01E01',
                'files': [
                  {'file_id': 7, 'file_name': 'demo.zh.srt'}
                ]
              }
            }
          ]
        });
      }
      if (request.url.path == '/api/v1/download') {
        expect(jsonDecode(request.body)['file_id'], 7);
        return _json({'link': 'https://example.test/sub.srt'});
      }
      if (request.url.path == '/sub.srt') {
        return http.Response.bytes(utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nhi\n'), 200);
      }
      return http.Response('nope', 404);
    });
    final provider = OpenSubtitlesProvider(apiKey: 'key', client: client);

    final hits = await provider.search(const SubtitleQuery(
      title: 'Demo',
      season: 1,
      episode: 1,
      language: 'zh-cn',
    ));
    expect(hits.single.language, 'zh-cn');
    expect(hits.single.format, 'srt');
    expect(hits.single.extra['file_id'], 7);

    final bytes = await provider.download(hits.single);
    expect(utf8.decode(bytes), contains('hi'));
    provider.close();
  });

  test('ASSRT searches and downloads a direct URL', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/sub/search') {
        expect(request.headers['Authorization'], 'Bearer token');
        return _json({
          'status': 0,
          'sub': {
            'subs': [
              {
                'id': 3,
                'native_name': 'Demo 字幕',
                'language': 'zh',
                'subtype': 'ass',
                'download_url': 'https://example.test/a.ass'
              }
            ]
          }
        });
      }
      if (request.url.path == '/a.ass') {
        return http.Response.bytes(utf8.encode('[Script Info]'), 200);
      }
      return http.Response('nope', 404);
    });
    final provider = AssrtProvider(token: 'token', client: client);

    final hits = await provider.search(const SubtitleQuery(title: 'Demo'));
    expect(hits.single.title, 'Demo 字幕');
    expect(hits.single.format, 'ass');
    final bytes = await provider.download(hits.single);
    expect(utf8.decode(bytes), contains('Script Info'));
    provider.close();
  });

  test('SubtitleStore writes into the video subs directory', () async {
    final temp = Directory.systemTemp.createTempSync('praxino-subs-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final video = '${temp.path}${Platform.pathSeparator}Demo S01E01.mkv';

    final file = await SubtitleStore.save(
      videoPath: video,
      bytes: utf8.encode('subtitle'),
      language: 'zh-cn',
      format: 'srt',
    );
    expect(file.path, contains('${Platform.pathSeparator}subs${Platform.pathSeparator}'));
    expect(file.path, endsWith('Demo S01E01.zh-cn.srt'));
    expect(file.readAsStringSync(), 'subtitle');
  });
}
