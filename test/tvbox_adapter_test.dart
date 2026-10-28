import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/sources/source_adapter.dart';
import 'package:praxino/core/sources/tvbox/tvbox_adapter.dart';

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

const _playUrl =
    r'第1集$https://example.test/1.m3u8#第2集$https://example.test/2.mp4$$$第1集$https://example.test/3.mp4';

const _detail = {
  'list': [
    {
      'vod_id': 42,
      'vod_name': '示例剧',
      'vod_play_url': _playUrl,
    }
  ],
};

void main() {
  test('parses vod_play_url into episode groups', () {
    final groups = TvBoxAdapter.parsePlayUrl(_playUrl);

    expect(groups, hasLength(2));
    expect(groups.first.episodes.map((e) => e.name), ['第1集', '第2集']);
    expect(groups.first.episodes.first.url, 'https://example.test/1.m3u8');
    expect(groups[1].episodes.single.url, 'https://example.test/3.mp4');
  });

  test('search and detail use ac=list / ac=detail', () async {
    final client = MockClient((request) async {
      if (request.url.queryParameters['ac'] == 'list') {
        expect(request.url.queryParameters['wd'], '示例');
        return _json({
          'list': [
            {'vod_id': 42, 'vod_name': '示例剧', 'vod_pic': 'p.jpg'}
          ]
        });
      }
      expect(request.url.queryParameters['ids'], '42');
      return _json(_detail);
    });

    final adapter = TvBoxAdapter(api: 'https://example.test/api.php', client: client);
    final hits = await adapter.search('示例');
    expect(hits.single.title, '示例剧');
    expect(hits.single.cover, 'p.jpg');

    final groups = await adapter.episodes(hits.single);
    expect(groups, hasLength(2));
    expect(groups.first.episodes.first.url, 'https://example.test/1.m3u8');
  });

  test('falls back to ac=detail when ac=list has no hits', () async {
    final client = MockClient((request) async {
      final ac = request.url.queryParameters['ac'];
      if (ac == 'list') return _json({'list': []});
      expect(ac, 'detail');
      expect(request.url.queryParameters['wd'], '示例');
      return _json({
        'list': [
          {'vod_id': 7, 'vod_name': '示例剧'}
        ]
      });
    });

    final adapter =
        TvBoxAdapter(api: 'https://example.test/api.php', client: client);
    final hits = await adapter.search('示例');
    expect(hits.single.title, '示例剧');
    expect(hits.single.url, '7');
  });

  test('parses XML responses', () async {
    const xml = '''
<rss><list><video>
  <id>7</id><name>XML 示例</name><pic>p.jpg</pic>
  <vod_play_url>第1集\$https://example.test/x.mp4</vod_play_url>
</video></list></rss>''';
    final adapter = TvBoxAdapter(
      api: 'https://example.test/api.php',
      client: MockClient((_) async =>
          http.Response.bytes(utf8.encode(xml), 200)),
    );

    final hits = await adapter.search('x');
    expect(hits.single.title, 'XML 示例');
    expect(hits.single.url, '7');

    final groups = await adapter.episodes(hits.single);
    expect(groups.single.episodes.single.url, 'https://example.test/x.mp4');
  });

  test('resolve only accepts http(s) and keeps headers', () async {
    final adapter = TvBoxAdapter(
      api: 'https://example.test/api.php',
      headers: {'Referer': 'https://example.test/'},
    );

    final stream = await adapter.resolve(
        const Episode(name: '1', url: 'https://example.test/a.mp4'));
    expect(stream!.headers['Referer'], 'https://example.test/');
    expect(
      await adapter.resolve(const Episode(name: '1', url: 'magnet:?xt=1')),
      isNull,
    );
  });

  test('surfaces HTTP failures', () async {
    final adapter = TvBoxAdapter(
      api: 'https://example.test/api.php',
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    expect(() => adapter.search('x'), throwsA(isA<TvBoxException>()));
  });
}
