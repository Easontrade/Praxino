import 'dart:convert';

import 'package:http/http.dart' as http;

import '../source_adapter.dart';

class StremioException implements Exception {
  const StremioException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StremioCatalog {
  const StremioCatalog({
    required this.type,
    required this.id,
    required this.name,
    this.extra = const [],
  });

  final String type;
  final String id;
  final String name;
  final List<String> extra;

  bool get supportsSearch => extra.contains('search');
}

class StremioManifest {
  const StremioManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.types,
    required this.resources,
    required this.catalogs,
  });

  final String id;
  final String name;
  final String version;
  final List<String> types;
  final List<String> resources;
  final List<StremioCatalog> catalogs;

  bool supports(String resource) => resources.contains(resource);

  factory StremioManifest.fromJson(Map<String, dynamic> json) {
    final resources = <String>[];
    final rawResources = json['resources'];
    if (rawResources is List) {
      for (final item in rawResources) {
        if (item is String) {
          resources.add(item);
        } else if (item is Map && item['name'] is String) {
          resources.add(item['name'] as String);
        }
      }
    }
    final catalogs = <StremioCatalog>[];
    final rawCatalogs = json['catalogs'];
    if (rawCatalogs is List) {
      for (final item in rawCatalogs) {
        if (item is! Map) continue;
        final type = item['type'];
        final id = item['id'];
        if (type is! String || id is! String) continue;
        final extra = <String>[];
        final rawExtra = item['extra'] ?? item['extraSupported'];
        if (rawExtra is List) {
          for (final e in rawExtra) {
            if (e is String) {
              extra.add(e);
            } else if (e is Map && e['name'] is String) {
              extra.add(e['name'] as String);
            }
          }
        }
        catalogs.add(StremioCatalog(
          type: type,
          id: id,
          name: '${item['name'] ?? id}',
          extra: extra,
        ));
      }
    }
    return StremioManifest(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'Stremio'}',
      version: '${json['version'] ?? ''}',
      types: [
        if (json['types'] is List)
          for (final type in json['types'] as List)
            if (type is String) type,
      ],
      resources: resources,
      catalogs: catalogs,
    );
  }
}

/// Stremio addon protocol: manifest, catalog search, meta and stream.
class StremioAdapter implements SourceAdapter {
  StremioAdapter({
    required this.baseUrl,
    required this.manifest,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final StremioManifest manifest;
  final http.Client _client;

  static Future<StremioAdapter> load(
    String baseUrl, {
    http.Client? client,
  }) async {
    final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final effective = client ?? http.Client();
    final response = await effective.get(Uri.parse('$normalized/manifest.json'));
    if (response.statusCode >= 400) {
      throw StremioException('Stremio manifest HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const StremioException('Stremio manifest 不是 JSON 对象');
    return StremioAdapter(
      baseUrl: normalized,
      manifest: StremioManifest.fromJson(decoded.cast<String, dynamic>()),
      client: effective,
    );
  }

  @override
  String get id => 'stremio:${manifest.id.isEmpty ? baseUrl : manifest.id}';

  @override
  String get name => manifest.name;

  @override
  Future<List<MediaSummary>> search(String keyword) async {
    final results = <MediaSummary>[];
    final seen = <String>{};
    for (final catalog in manifest.catalogs.where((c) => c.supportsSearch)) {
      final encoded = Uri.encodeComponent(keyword);
      final uri = Uri.parse(
        '$baseUrl/catalog/${catalog.type}/${catalog.id}/search=$encoded.json',
      );
      final data = await _getJson(uri);
      final metas = data['metas'];
      if (metas is! List) continue;
      for (final meta in metas) {
        if (meta is! Map) continue;
        final id = meta['id'];
        final title = meta['name'];
        if (id is! String || title is! String || !seen.add(id)) continue;
        results.add(MediaSummary(
          sourceId: this.id,
          title: title,
          url: '${catalog.type}|$id',
          cover: meta['poster'] is String ? meta['poster'] as String : null,
        ));
      }
    }
    return results;
  }

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async {
    final parts = media.url.split('|');
    if (parts.length < 2) return const [];
    final type = parts[0];
    final metaId = parts[1];
    final data = await _getJson(
      Uri.parse('$baseUrl/meta/$type/$metaId.json'),
    );
    final meta = data['meta'];
    if (meta is! Map) return const [];
    final videos = meta['videos'];
    if (videos is! List || videos.isEmpty) {
      return [
        EpisodeGroup(
          name: 'Stremio',
          episodes: [Episode(name: '正片', url: '$type|$metaId|$metaId')],
        ),
      ];
    }
    final episodes = <Episode>[];
    for (final video in videos) {
      if (video is! Map) continue;
      final id = video['id'];
      if (id is! String) continue;
      final season = video['season'];
      final number = video['episode'];
      final label = season is num && number is num
          ? 'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}'
          : '${video['title'] ?? id}';
      episodes.add(Episode(name: label, url: '$type|$metaId|$id'));
    }
    return [EpisodeGroup(name: 'Stremio', episodes: episodes)];
  }

  @override
  Future<PlayableStream?> resolve(Episode episode) async {
    final parts = episode.url.split('|');
    if (parts.length < 3) return null;
    final type = parts[0];
    final videoId = parts[2];
    final data = await _getJson(
      Uri.parse('$baseUrl/stream/$type/$videoId.json'),
    );
    final streams = data['streams'];
    if (streams is! List) return null;
    for (final stream in streams) {
      if (stream is! Map) continue;
      final url = stream['url'];
      if (url is! String || !(url.startsWith('http://') || url.startsWith('https://'))) {
        continue;
      }
      final headers = <String, String>{};
      final hints = stream['behaviorHints'];
      if (hints is Map) {
        final proxy = hints['proxyHeaders'];
        if (proxy is Map && proxy['request'] is Map) {
          final request = proxy['request'] as Map;
          if (request['headers'] is Map) {
            for (final entry in (request['headers'] as Map).entries) {
              if (entry.value is String) {
                headers['${entry.key}'] = entry.value as String;
              }
            }
          }
        }
        if (hints['headers'] is Map) {
          for (final entry in (hints['headers'] as Map).entries) {
            if (entry.value is String) {
              headers['${entry.key}'] = entry.value as String;
            }
          }
        }
      }
      final height = _heightOf(stream);
      return PlayableStream(url, headers: headers, height: height);
    }
    return null;
  }

  int? _heightOf(Map stream) {
    final height = stream['height'];
    if (height is num) return height.toInt();
    final resolution = '${stream['resolution'] ?? ''}';
    final match = RegExp(r'(\d{3,4})p?').firstMatch(resolution);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri);
    } on Exception catch (error) {
      throw StremioException('Stremio 请求失败：$error');
    }
    if (response.statusCode >= 400) {
      throw StremioException('Stremio HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const StremioException('Stremio 返回了非对象 JSON');
    return decoded.cast<String, dynamic>();
  }

  void close() => _client.close();
}
