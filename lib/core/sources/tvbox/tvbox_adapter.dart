import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../source_adapter.dart';

/// Apple CMS / TVBox JSON or XML API adapter.
///
/// Only `type: 0` (XML) and `type: 1` (JSON) are supported: those are plain
/// HTTP APIs. JAR/Python spider types are deliberately not executed.
class TvBoxAdapter implements SourceAdapter {
  TvBoxAdapter({
    required this.api,
    this.displayName = 'TVBox',
    this.headers = const {},
    http.Client? client,
  })  : _uri = Uri.parse(api),
        _client = client ?? http.Client();

  final String api;
  final String displayName;
  final Map<String, String> headers;
  final Uri _uri;
  final http.Client _client;

  @override
  String get id => 'tvbox:${_uri.host}:$displayName';

  @override
  String get name => displayName;

  @override
  Future<List<MediaSummary>> search(String keyword) async {
    var items = await _get({'ac': 'list', 'wd': keyword});
    if (items.isEmpty) {
      // A few deployments only implement keyword search through ac=detail.
      items = await _get({'ac': 'detail', 'wd': keyword});
    }
    return [
      for (final item in items)
        if (item.id.isNotEmpty)
          MediaSummary(
            sourceId: id,
            title: item.title,
            url: item.id,
            cover: item.cover,
          ),
    ];
  }

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async {
    final items = await _get({'ac': 'detail', 'ids': media.url});
    if (items.isEmpty) return const [];
    return parsePlayUrl(items.first.playUrl);
  }

  @override
  Future<PlayableStream?> resolve(Episode episode) async {
    final url = episode.url.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    return PlayableStream(url, headers: headers);
  }

  /// Parses `线路$集名$地址#集名$地址$$$线路2…`.
  static List<EpisodeGroup> parsePlayUrl(String raw) {
    final groups = <EpisodeGroup>[];
    for (final block in raw.split(r'$$$')) {
      final episodes = <Episode>[];
      for (final entry in block.split('#')) {
        final parts = entry.split(r'$');
        if (parts.length < 2) continue;
        final url = parts.sublist(1).join(r'$').trim();
        if (url.isEmpty) continue;
        episodes.add(Episode(name: parts.first.trim(), url: url));
      }
      if (episodes.isNotEmpty) {
        groups.add(EpisodeGroup(
          name: '线路 ${groups.length + 1}',
          episodes: episodes,
        ));
      }
    }
    return groups;
  }

  Future<List<_TvBoxItem>> _get(Map<String, String> query) async {
    final uri = _uri.replace(
      queryParameters: {..._uri.queryParameters, ...query},
    );
    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
        ...headers,
      });
    } on Exception catch (error) {
      throw TvBoxException('请求失败：$error');
    }
    if (response.statusCode >= 400) {
      throw TvBoxException('HTTP ${response.statusCode}');
    }
    return _parseBody(response.bodyBytes);
  }

  static List<_TvBoxItem> _parseBody(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final json = _tryJson(text);
    if (json != null) return _fromJson(json);
    try {
      return _fromXml(text);
    } on XmlException catch (error) {
      throw TvBoxException('无法解析响应：${error.message}');
    }
  }

  static Map? _tryJson(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static List<_TvBoxItem> _fromJson(Map<dynamic, dynamic> data) {
    final list = data['list'];
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map)
          _TvBoxItem(
            id: '${item['vod_id'] ?? ''}',
            title: '${item['vod_name'] ?? ''}',
            cover: item['vod_pic'] is String ? item['vod_pic'] as String : null,
            playUrl: '${item['vod_play_url'] ?? ''}',
          ),
    ];
  }

  static List<_TvBoxItem> _fromXml(String text) {
    final document = XmlDocument.parse(text);
    return [
      for (final video in document.findAllElements('video'))
        _TvBoxItem(
          id: _text(video, 'id'),
          title: _text(video, 'name'),
          cover: _text(video, 'pic').isEmpty ? null : _text(video, 'pic'),
          playUrl: _text(video, 'vod_play_url').isEmpty
              ? _text(video, 'dl')
              : _text(video, 'vod_play_url'),
        ),
    ];
  }

  static String _text(XmlElement parent, String name) {
    final child = parent.getElement(name);
    return child?.innerText.trim() ?? '';
  }

  void close() => _client.close();
}

class _TvBoxItem {
  const _TvBoxItem({
    required this.id,
    required this.title,
    required this.playUrl,
    this.cover,
  });

  final String id;
  final String title;
  final String? cover;
  final String playUrl;
}

class TvBoxException implements Exception {
  const TvBoxException(this.message);

  final String message;

  @override
  String toString() => message;
}
