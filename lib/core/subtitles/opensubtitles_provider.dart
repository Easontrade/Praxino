import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subtitle_provider.dart';

/// OpenSubtitles REST API v1.
class OpenSubtitlesProvider implements SubtitleProvider {
  OpenSubtitlesProvider({
    required this.apiKey,
    this.appVersion = '0.1.0',
    String? userAgent,
    this.token,
    http.Client? client,
    this.baseUrl = 'https://api.opensubtitles.com/api/v1',
  })  : _userAgent = userAgent ?? 'Praxino v$appVersion',
        _client = client ?? http.Client();

  final String apiKey;
  final String appVersion;
  final String _userAgent;
  String? token;
  final String baseUrl;
  final http.Client _client;

  @override
  String get id => 'opensubtitles';

  @override
  String get name => 'OpenSubtitles';

  Map<String, String> get _headers => {
        'Api-Key': apiKey,
        'User-Agent': _userAgent,
        'Accept': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  /// Logs in and stores the token for later downloads.
  Future<OpenSubtitlesLogin> login({
    required String username,
    required String password,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$baseUrl/login'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
    } on Exception catch (error) {
      throw SubtitleException('OpenSubtitles 登录失败：$error');
    }
    if (response.statusCode >= 400) {
      throw SubtitleAuthException(
        'OpenSubtitles 登录失败：HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['token'] is! String) {
      throw const SubtitleAuthException('OpenSubtitles 没有返回 token');
    }
    token = decoded['token'] as String;
    return OpenSubtitlesLogin(
      token: token!,
      remainingDownloads: decoded['remaining_downloads'] is num
          ? (decoded['remaining_downloads'] as num).toInt()
          : null,
      userId: decoded['user_id'] is num
          ? (decoded['user_id'] as num).toInt()
          : null,
    );
  }

  @override
  Future<List<SubtitleCandidate>> search(SubtitleQuery query) async {
    final uri = Uri.parse('$baseUrl/subtitles').replace(queryParameters: {
      'query': query.title,
      'languages': query.language ?? 'zh-cn,zh-tw,en',
      'type': query.episode == null ? 'movie' : 'episode',
      if (query.season != null) 'season_number': '${query.season}',
      if (query.episode != null) 'episode_number': '${query.episode}',
    });
    final data = await _getJson(uri);
    final entries = data['data'];
    if (entries is! List) return const [];
    final result = <SubtitleCandidate>[];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final attributes = entry['attributes'];
      if (attributes is! Map) continue;
      final files = attributes['files'];
      if (files is! List || files.isEmpty || files.first is! Map) continue;
      final file = files.first as Map;
      final fileId = file['file_id'];
      if (fileId is! num) continue;
      final fileName = '${file['file_name'] ?? ''}';
      final language = '${attributes['language'] ?? ''}';
      result.add(SubtitleCandidate(
        provider: id,
        id: '${entry['id'] ?? fileId}',
        title: '${attributes['release'] ?? attributes['feature_details']?['title'] ?? fileName}',
        language: language.isEmpty ? 'unknown' : language,
        format: _extension(fileName),
        score: attributes['download_count'] is num
            ? (attributes['download_count'] as num).toInt()
            : 0,
        extra: {'file_id': fileId.toInt(), 'file_name': fileName},
      ));
    }
    return result;
  }

  @override
  Future<List<int>> download(SubtitleCandidate candidate) async {
    final fileId = candidate.extra['file_id'];
    if (fileId is! int) throw const SubtitleException('缺少 file_id');
    final response = await _client.post(
      Uri.parse('$baseUrl/download'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'file_id': fileId}),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SubtitleAuthException('OpenSubtitles token 已过期，请重新登录');
    }
    if (response.statusCode == 406 || response.statusCode == 429) {
      throw const SubtitleQuotaException('OpenSubtitles 下载额度已用完');
    }
    if (response.statusCode >= 400) {
      throw SubtitleException('OpenSubtitles 下载 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['link'] is! String) {
      throw const SubtitleException('OpenSubtitles 没有返回下载地址');
    }
    final link = decoded['link'] as String;
    final file = await _client.get(Uri.parse(link), headers: {
      'User-Agent': _userAgent,
    });
    if (file.statusCode >= 400) {
      throw SubtitleException('字幕文件 HTTP ${file.statusCode}');
    }
    return file.bodyBytes;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers);
    } on Exception catch (error) {
      throw SubtitleException('OpenSubtitles 请求失败：$error');
    }
    if (response.statusCode >= 400) {
      throw SubtitleException('OpenSubtitles HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const SubtitleException('OpenSubtitles 返回非对象 JSON');
    return decoded.cast<String, dynamic>();
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'srt';
    return name.substring(dot + 1).toLowerCase();
  }

  void close() => _client.close();
}
