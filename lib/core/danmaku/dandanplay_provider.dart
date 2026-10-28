import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'danmaku_engine.dart';

class DandanplayMatch {
  const DandanplayMatch({
    required this.episodeId,
    required this.animeTitle,
    required this.episodeTitle,
  });

  final int episodeId;
  final String animeTitle;
  final String episodeTitle;
}

class DandanplayEpisode {
  const DandanplayEpisode({
    required this.episodeId,
    required this.animeTitle,
    required this.episodeTitle,
  });

  final int episodeId;
  final String animeTitle;
  final String episodeTitle;
}

class DandanplayException implements Exception {
  const DandanplayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dandanplay open API client using signature authentication.
///
/// AppId/AppSecret are supplied by the caller (environment/settings); they are
/// never hardcoded in the repository.
class DandanplayClient {
  DandanplayClient({
    required this.appId,
    required this.appSecret,
    http.Client? client,
    this.baseUrl = 'https://api.dandanplay.net',
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final String appId;
  final String appSecret;
  final String baseUrl;
  final http.Client _client;
  final DateTime Function() _clock;

  Future<DandanplayMatch?> match({
    required String fileName,
    required String fileHash,
    required int fileSize,
    String? videoDuration,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/v2/match',
      body: {
        'fileName': fileName,
        'fileHash': fileHash,
        'fileSize': fileSize,
        'videoDuration': ?videoDuration,
      },
    );
    if (response['isMatched'] != true) return null;
    final matches = response['matches'];
    if (matches is! List || matches.isEmpty) return null;
    final first = matches.first;
    if (first is! Map) return null;
    final id = first['episodeId'];
    if (id is! num) return null;
    return DandanplayMatch(
      episodeId: id.toInt(),
      animeTitle: '${first['animeTitle'] ?? ''}',
      episodeTitle: '${first['episodeTitle'] ?? ''}',
    );
  }

  Future<List<DandanplayEpisode>> searchEpisodes({
    required String anime,
    String? episode,
  }) async {
    final response = await _send(
      method: 'GET',
      path: '/api/v2/search/episodes',
      query: {
        'anime': anime,
        if (episode != null && episode.isNotEmpty) 'episode': episode,
      },
    );
    final result = <DandanplayEpisode>[];

    // The live API groups episodes per anime, and the episode objects do not
    // repeat the anime title:
    //   {"animes":[{"animeTitle":"…","episodes":[{"episodeId":…}]}]}
    final animes = response['animes'];
    if (animes is List) {
      for (final animeEntry in animes) {
        if (animeEntry is! Map) continue;
        final animeTitle = '${animeEntry['animeTitle'] ?? ''}';
        final episodes = animeEntry['episodes'];
        if (episodes is! List) continue;
        for (final entry in episodes) {
          final parsed = _episode(entry, animeTitle);
          if (parsed != null) result.add(parsed);
        }
      }
    }
    if (result.isNotEmpty) return result;

    // Some compatible servers return a flat list instead.
    final episodes = response['episodes'];
    if (episodes is! List) return result;
    for (final entry in episodes) {
      final parsed = _episode(entry, '');
      if (parsed != null) result.add(parsed);
    }
    return result;
  }

  static DandanplayEpisode? _episode(Object? entry, String animeTitle) {
    if (entry is! Map) return null;
    final id = entry['episodeId'];
    if (id is! num) return null;
    return DandanplayEpisode(
      episodeId: id.toInt(),
      animeTitle: animeTitle.isNotEmpty
          ? animeTitle
          : '${entry['animeTitle'] ?? ''}',
      episodeTitle: '${entry['episodeTitle'] ?? ''}',
    );
  }

  Future<List<DanmakuItem>> comments(int episodeId) async {
    final response = await _send(
      method: 'GET',
      path: '/api/v2/comment/$episodeId',
      query: {'withRelated': 'true', 'chConvert': '1'},
    );
    final comments = response['comments'];
    if (comments is! List) return const [];
    final result = <DanmakuItem>[];
    for (final comment in comments) {
      if (comment is! Map) continue;
      final text = comment['m'];
      final p = comment['p'];
      if (text is! String || text.isEmpty || p is! String) continue;
      final parts = p.split(',');
      if (parts.length < 2) continue;
      final seconds = double.tryParse(parts[0]);
      if (seconds == null) continue;
      final modeCode = int.tryParse(parts[1]) ?? 1;
      final rgb = parts.length > 2 ? int.tryParse(parts[2]) ?? 0xFFFFFF : 0xFFFFFF;
      result.add(DanmakuItem(
        time: Duration(milliseconds: (seconds * 1000).round()),
        text: text,
        mode: switch (modeCode) {
          5 => DanmakuMode.top,
          4 => DanmakuMode.bottom,
          _ => DanmakuMode.scroll,
        },
        color: 0xFF000000 | (rgb & 0xFFFFFF),
      ));
    }
    return result;
  }

  Map<String, String> signatureHeaders(String path) {
    final timestamp = (_clock().millisecondsSinceEpoch ~/ 1000).toString();
    final raw = '$appId$timestamp$path$appSecret';
    final signature = base64Encode(sha256.convert(utf8.encode(raw)).bytes);
    return {
      'X-AppId': appId,
      'X-Timestamp': timestamp,
      'X-Signature': signature,
    };
  }

  Future<Map<String, dynamic>> _send({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = {
      ...signatureHeaders(path),
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final http.Response response;
    try {
      response = method == 'POST'
          ? await _client.post(uri, headers: headers, body: jsonEncode(body))
          : await _client.get(uri, headers: headers);
    } on Exception catch (error) {
      throw DandanplayException('弹弹play 请求失败：$error');
    }
    if (response.statusCode >= 400) {
      throw DandanplayException('弹弹play HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const DandanplayException('弹弹play 返回了非对象 JSON');
    }
    if (decoded['success'] == false) {
      throw DandanplayException('弹弹play：${decoded['errorMessage'] ?? '请求失败'}');
    }
    return decoded;
  }

  void close() => _client.close();
}
