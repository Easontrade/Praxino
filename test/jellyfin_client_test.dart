import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/sources/jellyfin/jellyfin_adapter.dart';
import 'package:praxino/core/sources/jellyfin/jellyfin_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  test('logs in and returns a client with token', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/Users/AuthenticateByName');
      expect(request.headers['X-Emby-Authorization'], contains('Praxino'));
      final body = jsonDecode(request.body);
      expect(body['Username'], 'demo');
      return _json({
        'AccessToken': 'token-1',
        'User': {'Id': 'user-1', 'Name': 'demo'}
      });
    });

    final api = await JellyfinClient.login(
      baseUrl: 'https://example.test',
      username: 'demo',
      password: 'pw',
      client: client,
    );
    expect(api.token, 'token-1');
    expect(api.userId, 'user-1');
    expect(api.headers['X-Emby-Token'], 'token-1');
  });

  test('lists views and items', () async {
    final api = JellyfinClient(
      baseUrl: 'https://example.test',
      token: 't',
      userId: 'u',
      deviceId: 'd',
      client: MockClient((request) async {
        if (request.url.path == '/Users/u/Views') {
          return _json({
            'Items': [
              {'Id': 'v1', 'Name': '电影', 'Type': 'CollectionFolder'}
            ]
          });
        }
        expect(request.url.queryParameters['ParentId'], 'v1');
        return _json({
          'Items': [
            {
              'Id': 'm1',
              'Name': 'Demo',
              'Type': 'Movie',
              'RunTimeTicks': 10000000,
              'ImageTags': {'Primary': 'tag'}
            }
          ]
        });
      }),
    );
    expect((await api.views()).single.name, '电影');
    final items = await api.items('v1');
    expect(items.single.name, 'Demo');
    expect(items.single.imageTag, 'tag');
    api.close();
  });

  test('builds direct-play URL and Chinese-first subtitle list', () async {
    final api = JellyfinClient(
      baseUrl: 'https://example.test',
      token: 't',
      userId: 'u',
      deviceId: 'd',
      client: MockClient((request) async {
        expect(request.url.path, '/Users/u/Items/m1');
        return _json({
          'MediaSources': [
            {
              'Id': 'source-1',
              'MediaStreams': [
                {'Type': 'Subtitle', 'Index': 3, 'Language': 'eng', 'Codec': 'srt'},
                {'Type': 'Subtitle', 'Index': 2, 'Language': 'chi', 'Codec': 'ass'},
                {'Type': 'Audio', 'Index': 1}
              ]
            }
          ]
        });
      }),
    );
    final playback = await api.playback(const JellyfinItem(
      id: 'm1',
      name: 'Demo',
      type: 'Movie',
    ));
    expect(playback.url, 'https://example.test/Videos/m1/stream?static=true&mediaSourceId=source-1');
    expect(playback.headers['X-Emby-Token'], 't');
    expect(playback.subtitles.first.language, 'chi');
    expect(playback.subtitles.first.url, contains('/Subtitles/2/Stream.ass'));
    api.close();
  });

  test('adapter searches, expands movies and resolves subtitles', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/Users/u/Items') {
        return _json({
          'Items': [
            {'Id': 'm1', 'Name': 'Demo', 'Type': 'Movie'}
          ]
        });
      }
      if (request.url.path == '/Users/u/Items/m1') {
        return _json({
          'MediaSources': [
            {
              'Id': 's1',
              'MediaStreams': [
                {'Type': 'Subtitle', 'Index': 2, 'Language': 'chi', 'Codec': 'srt'}
              ]
            }
          ]
        });
      }
      return _json({}, status: 404);
    });
    final api = JellyfinClient(
      baseUrl: 'https://example.test',
      token: 't',
      userId: 'u',
      deviceId: 'd',
      client: client,
    );
    final adapter = JellyfinAdapter(name: 'Home', client: api);
    final hits = await adapter.search('Demo');
    expect(hits.single.title, 'Demo');
    final groups = await adapter.episodes(hits.single);
    expect(groups.single.episodes.single.url, 'Movie|m1');
    final stream = await adapter.resolve(groups.single.episodes.single);
    expect(stream!.subtitleLanguages, ['chi']);
    expect(stream.subtitleUrls['chi'], contains('/Subtitles/2/Stream.srt'));
    api.close();
  });

  test('reports progress ticks and token expiry', () async {
    var body = <String, dynamic>{};
    final api = JellyfinClient(
      baseUrl: 'https://example.test',
      token: 't',
      userId: 'u',
      deviceId: 'd',
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({});
      }),
    );
    await api.reportProgress(
      itemId: 'm1',
      position: const Duration(seconds: 5),
    );
    expect(body['PositionTicks'], 50000000);
    expect(body['PlayMethod'], 'DirectPlay');

    final expired = JellyfinClient(
      baseUrl: 'https://example.test',
      token: 'bad',
      userId: 'u',
      deviceId: 'd',
      client: MockClient((_) async => _json({}, status: 401)),
    );
    expect(
      () => expired.items('v1'),
      throwsA(isA<JellyfinAuthException>()),
    );
    api.close();
    expired.close();
  });

  test('server settings round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    const server = JellyfinServer(
      name: 'Home',
      baseUrl: 'https://example.test',
      userId: 'u',
      token: 't',
      deviceId: 'd',
    );
    await settings.saveJellyfinServers([server]);
    expect(settings.jellyfinServers.single.name, 'Home');
    expect(settings.jellyfinServers.single.client().userId, 'u');
  });
}
