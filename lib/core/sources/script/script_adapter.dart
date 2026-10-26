import 'dart:convert';

import '../source_adapter.dart';
import 'quickjs_host.dart';

/// A user-supplied JavaScript source, executed in the QuickJS sandbox.
///
/// Scripts define async `search(keyword)`, `episodes(media)` and
/// `resolve(episode)` functions returning JSON-compatible values. There is no
/// file, process or native-module access; only `fetch`, `parseHtml` and
/// `console.log` are available.
class ScriptAdapter implements SourceAdapter {
  ScriptAdapter({
    required this.id,
    required this.name,
    required this.script,
    QuickJsHost? host,
  }) : _host = host ?? QuickJsHost();

  @override
  final String id;
  @override
  final String name;
  final String script;
  final QuickJsHost _host;

  String get hash => scriptHash(script);

  @override
  Future<List<MediaSummary>> search(String keyword) async {
    final data = await _call('search', keyword);
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map && item['title'] is String && item['url'] is String)
          MediaSummary(
            sourceId: id,
            title: item['title'] as String,
            url: item['url'] as String,
            cover: item['cover'] is String ? item['cover'] as String : null,
          ),
    ];
  }

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async {
    final data = await _call('episodes', {
      'title': media.title,
      'url': media.url,
      'cover': media.cover,
    });
    if (data is! List) return const [];
    final groups = <EpisodeGroup>[];
    for (final group in data) {
      if (group is! Map) continue;
      final rawEpisodes = group['episodes'];
      if (rawEpisodes is! List) continue;
      groups.add(EpisodeGroup(
        name: '${group['name'] ?? '线路'}',
        episodes: [
          for (final episode in rawEpisodes)
            if (episode is Map &&
                episode['name'] is String &&
                episode['url'] is String)
              Episode(
                name: episode['name'] as String,
                url: episode['url'] as String,
              ),
        ],
      ));
    }
    return groups;
  }

  @override
  Future<PlayableStream?> resolve(Episode episode) async {
    final data = await _call('resolve', {
      'name': episode.name,
      'url': episode.url,
    });
    if (data is! Map) return null;
    final url = data['url'];
    if (url is! String || !(url.startsWith('http://') || url.startsWith('https://'))) {
      return null;
    }
    final headers = <String, String>{};
    final rawHeaders = data['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.value is String) headers['${entry.key}'] = entry.value as String;
      }
    }
    final height = data['height'];
    return PlayableStream(
      url,
      headers: headers,
      height: height is num ? height.toInt() : null,
    );
  }

  Future<Object?> _call(String function, Object? argument) {
    final code = '''
$script
$quickJsHelpers
(async () => {
  const value = await $function(${jsonEncode(argument)});
  return JSON.stringify(value ?? null);
})()
''';
    return _host.runJson(code);
  }

  void close() => _host.close();
}
