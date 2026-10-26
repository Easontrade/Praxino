import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subtitle_provider.dart';

/// OpenSubtitles REST API v1.
class OpenSubtitlesProvider implements SubtitleProvider {
  OpenSubtitlesProvider({
    required this.apiKey,
    this.userAgent = 'Praxino v1',
    this.token,
    http.Client? client,
    this.baseUrl = 'https://api.opensubtitles.com/api/v1',
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String userAgent;
  final String? token;
  final String baseUrl;
  final http.Client _client;

  @override
  String get id => 'opensubtitles';

  @override
  String get name => 'OpenSubtitles';

  Map<String, String> get _headers => {
        'Api-Key': apiKey,
        'User-Agent': userAgent,
        'Accept': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

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
    if (response.statusCode >= 400) {
      throw SubtitleException('OpenSubtitles 下载 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['link'] is! String) {
      throw const SubtitleException('OpenSubtitles 没有返回下载地址');
    }
    final link = decoded['link'] as String;
    final file = await _client.get(Uri.parse(link), headers: {
      'User-Agent': userAgent,
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
