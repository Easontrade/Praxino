import 'dart:convert';

import 'package:http/http.dart' as http;

class JellyfinException implements Exception {
  const JellyfinException(this.message);

  final String message;

  @override
  String toString() => message;
}

class JellyfinAuthException extends JellyfinException {
  const JellyfinAuthException(super.message);
}

/// Persisted login for one Jellyfin/Emby server.
class JellyfinServer {
  const JellyfinServer({
    required this.name,
    required this.baseUrl,
    required this.userId,
    required this.token,
    required this.deviceId,
    this.isEmby = false,
  });

  final String name;
  final String baseUrl;
  final String userId;
  final String token;
  final String deviceId;
  final bool isEmby;

  JellyfinClient client() => JellyfinClient(
        baseUrl: baseUrl,
        token: token,
        userId: userId,
        deviceId: deviceId,
        isEmby: isEmby,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'baseUrl': baseUrl,
        'userId': userId,
        'token': token,
        'deviceId': deviceId,
        'isEmby': isEmby,
      };

  static JellyfinServer? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final baseUrl = raw['baseUrl'];
    final userId = raw['userId'];
    final token = raw['token'];
    if (name is! String ||
        baseUrl is! String ||
        userId is! String ||
        token is! String) {
      return null;
    }
    return JellyfinServer(
      name: name,
      baseUrl: baseUrl,
      userId: userId,
      token: token,
      deviceId: raw['deviceId'] is String ? raw['deviceId'] as String : 'praxino-windows',
      isEmby: raw['isEmby'] == true,
    );
  }
}

class JellyfinItem {
  const JellyfinItem({
    required this.id,
    required this.name,
    required this.type,
    this.seriesName,
    this.seasonNumber,
    this.indexNumber,
    this.imageTag,
    this.runTimeTicks,
  });

  final String id;
  final String name;
  final String type;
  final String? seriesName;
  final int? seasonNumber;
  final int? indexNumber;
  final String? imageTag;
  final int? runTimeTicks;

  String get displayName {
    if (type == 'Episode' && seriesName != null) {
      final season = seasonNumber == null
          ? ''
          : 'S${seasonNumber!.toString().padLeft(2, '0')}';
      final episode = indexNumber == null
          ? ''
          : 'E${indexNumber!.toString().padLeft(2, '0')}';
      return '$seriesName · $season$episode · $name';
    }
    return name;
  }
}

class JellyfinSubtitle {
  const JellyfinSubtitle({
    required this.index,
    required this.language,
    required this.url,
  });

  final int index;
  final String language;
  final String url;
}

class JellyfinPlayback {
  const JellyfinPlayback({
    required this.url,
    required this.headers,
    this.subtitles = const [],
  });

  final String url;
  final Map<String, String> headers;
  final List<JellyfinSubtitle> subtitles;
}

/// Jellyfin and Emby share the same base API; [isEmby] only changes naming.
class JellyfinClient {
  JellyfinClient({
    required this.baseUrl,
    required this.token,
    required this.userId,
    required this.deviceId,
    this.isEmby = false,
    this.appVersion = '0.1.0',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final String userId;
  final String deviceId;
  final bool isEmby;
  final String appVersion;
  final http.Client _client;

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get headers => {
        'X-Emby-Authorization':
            'MediaBrowser Client="Praxino", Device="Windows", '
                'DeviceId="$deviceId", Version="$appVersion", Token="$token"',
        'X-Emby-Token': token,
        'Accept': 'application/json',
      };

  static Future<JellyfinClient> login({
    required String baseUrl,
    required String username,
    required String password,
    bool isEmby = false,
    String? deviceId,
    String appVersion = '0.1.0',
    http.Client? client,
  }) async {
    final effective = client ?? http.Client();
    final device = deviceId ?? 'praxino-windows';
    final response = await effective.post(
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/Users/AuthenticateByName'),
      headers: {
        'X-Emby-Authorization':
            'MediaBrowser Client="Praxino", Device="Windows", '
                'DeviceId="$device", Version="$appVersion"',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'Username': username, 'Pw': password}),
    );
    if (response.statusCode == 401) {
      throw const JellyfinAuthException('Jellyfin/Emby 用户名或密码错误');
    }
    if (response.statusCode >= 400) {
      throw JellyfinException('登录 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const JellyfinException('登录返回非对象 JSON');
    final accessToken = decoded['AccessToken'];
    final user = decoded['User'];
    final id = user is Map ? user['Id'] : null;
    if (accessToken is! String || id is! String) {
      throw const JellyfinException('登录没有返回 token/userId');
    }
    return JellyfinClient(
      baseUrl: baseUrl,
      token: accessToken,
      userId: id,
      deviceId: device,
      isEmby: isEmby,
      appVersion: appVersion,
      client: effective,
    );
  }

  Future<List<JellyfinItem>> views() async {
    final data = await _get('/Users/$userId/Views');
    return _items(data);
  }

  Future<List<JellyfinItem>> items(String parentId) async {
    final data = await _get('/Users/$userId/Items', {
      'ParentId': parentId,
      'Recursive': 'true',
      'IncludeItemTypes': 'Movie,Series,Episode,BoxSet',
      'Fields': 'PrimaryImageAspectRatio,RunTimeTicks',
      'SortBy': 'SortName',
    });
    return _items(data);
  }

  Future<List<JellyfinItem>> search(String term) async {
    final data = await _get('/Users/$userId/Items', {
      'SearchTerm': term,
      'Recursive': 'true',
      'IncludeItemTypes': 'Movie,Series,Episode,BoxSet',
      'Fields': 'PrimaryImageAspectRatio,RunTimeTicks',
      'Limit': '50',
    });
    return _items(data);
  }

  Future<JellyfinPlayback> playback(JellyfinItem item) async {
    final data = await _get('/Users/$userId/Items/${item.id}');
    final sources = data['MediaSources'];
    final source = sources is List && sources.isNotEmpty && sources.first is Map
        ? sources.first as Map
        : null;
    final mediaSourceId = source?['Id'] is String
        ? source!['Id'] as String
        : item.id;
    final subtitles = <JellyfinSubtitle>[];
    final streams = source?['MediaStreams'];
    if (streams is List) {
      for (final stream in streams) {
        if (stream is! Map || stream['Type'] != 'Subtitle') continue;
        final index = stream['Index'];
        if (index is! num) continue;
        final language = '${stream['Language'] ?? 'unknown'}';
        final codec = '${stream['Codec'] ?? 'srt'}';
        final url = '$_root/Videos/${item.id}/$mediaSourceId/Subtitles/$index/Stream.$codec';
        subtitles.add(JellyfinSubtitle(
          index: index.toInt(),
          language: language,
          url: url,
        ));
      }
    }
    subtitles.sort((a, b) => _languageRank(a.language).compareTo(_languageRank(b.language)));
    return JellyfinPlayback(
      url: '$_root/Videos/${item.id}/stream?static=true&mediaSourceId=$mediaSourceId',
      headers: {'X-Emby-Token': token},
      subtitles: subtitles,
    );
  }

  Future<void> reportProgress({
    required String itemId,
    required Duration position,
    bool paused = false,
  }) async {
    await _post('/Sessions/Playing/Progress', {
      'ItemId': itemId,
      'PositionTicks': position.inMicroseconds * 10,
      'IsPaused': paused,
      'PlayMethod': 'DirectPlay',
      'CanSeek': true,
    });
  }

  Future<Duration> resumePosition(String itemId) async {
    final data = await _get('/Users/$userId/Items/$itemId');
    final userData = data['UserData'];
    final ticks = userData is Map ? userData['PlaybackPositionTicks'] : null;
    if (ticks is! num || ticks <= 0) return Duration.zero;
    return Duration(microseconds: ticks.toInt() ~/ 10);
  }

  static int _languageRank(String language) {
    final lower = language.toLowerCase();
    if (lower.startsWith('zh') || lower.contains('chi')) return 0;
    if (lower.startsWith('en')) return 1;
    return 2;
  }

  List<JellyfinItem> _items(Map<String, dynamic> data) {
    final raw = data['Items'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && item['Id'] is String && item['Name'] is String)
          JellyfinItem(
            id: item['Id'] as String,
            name: item['Name'] as String,
            type: '${item['Type'] ?? ''}',
            seriesName: item['SeriesName'] is String ? item['SeriesName'] as String : null,
            seasonNumber: item['ParentIndexNumber'] is num
                ? (item['ParentIndexNumber'] as num).toInt()
                : null,
            indexNumber: item['IndexNumber'] is num
                ? (item['IndexNumber'] as num).toInt()
                : null,
            imageTag: item['ImageTags'] is Map && item['ImageTags']['Primary'] is String
                ? item['ImageTags']['Primary'] as String
                : null,
            runTimeTicks: item['RunTimeTicks'] is num
                ? (item['RunTimeTicks'] as num).toInt()
                : null,
          ),
    ];
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) async {
    final response = await _client.get(
      Uri.parse('$_root$path').replace(queryParameters: query),
      headers: headers,
    );
    return _decode(response);
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    final response = await _client.post(
      Uri.parse('$_root$path'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        throw const JellyfinAuthException('Jellyfin/Emby token 已过期');
      }
      throw JellyfinException('请求 HTTP ${response.statusCode}');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 401) {
      throw const JellyfinAuthException('Jellyfin/Emby token 已过期');
    }
    if (response.statusCode >= 400) {
      throw JellyfinException('请求 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const JellyfinException('返回非对象 JSON');
    return decoded.cast<String, dynamic>();
  }

  void close() => _client.close();
}
