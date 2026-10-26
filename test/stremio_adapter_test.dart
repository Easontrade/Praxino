import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/sources/source_adapter.dart';
import 'package:praxino/core/sources/stremio/stremio_adapter.dart';

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  test('loads manifest and searches a catalog', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/manifest.json') {
        return _json({
          'id': 'org.example.demo',
          'name': 'Demo Addon',
          'version': '1.0.0',
          'types': ['movie'],
          'resources': ['catalog', 'meta', 'stream'],
          'catalogs': [
            {
              'type': 'movie',
              'id': 'top',
              'name': 'Top',
              'extra': [
                {'name': 'search'}
              ],
            }
          ],
        });
      }
      if (request.url.path.startsWith('/catalog/movie/top/search=')) {
        return _json({
          'metas': [
            {'id': 'tt1', 'name': 'Demo Movie', 'poster': 'p.jpg'}
          ]
        });
      }
      return http.Response('not found', 404);
    });

    final adapter = await StremioAdapter.load(
      'https://example.test/',
      client: client,
    );
    expect(adapter.id, 'stremio:org.example.demo');
    final hits = await adapter.search('demo');
    expect(hits.single.title, 'Demo Movie');
    expect(hits.single.url, 'movie|tt1');
    adapter.close();
  });

  test('meta videos become episodes and streams carry headers', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/meta/series/tt1.json') {
        return _json({
          'meta': {
            'id': 'tt1',
            'name': 'Demo',
            'videos': [
              {'id': 'tt1:1:1', 'season': 1, 'episode': 1}
            ],
          }
        });
      }
      if (request.url.path == '/stream/series/tt1:1:1.json') {
        return _json({
          'streams': [
            {
              'url': 'https://example.test/video.m3u8',
              'height': 1080,
              'behaviorHints': {
                'proxyHeaders': {
                  'request': {
                    'headers': {'Referer': 'https://example.test/'}
                  }
                }
              }
            }
          ]
        });
      }
      return http.Response('not found', 404);
    });
    final adapter = StremioAdapter(
      baseUrl: 'https://example.test',
      manifest: const StremioManifest(
        id: 'x',
        name: 'x',
        version: '1',
        types: ['series'],
        resources: ['meta', 'stream'],
        catalogs: [],
      ),
      client: client,
    );

    final groups = await adapter.episodes(
      const MediaSummary(sourceId: 'x', title: 'Demo', url: 'series|tt1'),
    );
    expect(groups.single.episodes.single.name, 'S01E01');

    final stream = await adapter.resolve(groups.single.episodes.single);
    expect(stream!.url, 'https://example.test/video.m3u8');
    expect(stream.height, 1080);
    expect(stream.headers['Referer'], 'https://example.test/');
    adapter.close();
  });

  test('movies without videos get a single feature episode', () async {
    final adapter = StremioAdapter(
      baseUrl: 'https://example.test',
      manifest: const StremioManifest(
        id: 'x',
        name: 'x',
        version: '1',
        types: ['movie'],
        resources: ['meta'],
        catalogs: [],
      ),
      client: MockClient((_) async => _json({
            'meta': {'id': 'tt2', 'name': 'Movie'}
          })),
    );
    final groups = await adapter.episodes(
      const MediaSummary(sourceId: 'x', title: 'Movie', url: 'movie|tt2'),
    );
    expect(groups.single.episodes.single.url, 'movie|tt2|tt2');
    adapter.close();
  });
}
