import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subtitle_provider.dart';

/// ASSRT (伪射手) subtitle API.
class AssrtProvider implements SubtitleProvider {
  AssrtProvider({
    required this.token,
    http.Client? client,
    this.baseUrl = 'https://api.assrt.net/v1',
  }) : _client = client ?? http.Client();

  final String token;
  final String baseUrl;
  final http.Client _client;

  @override
  String get id => 'assrt';

  @override
  String get name => 'ASSRT';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  @override
  Future<List<SubtitleCandidate>> search(SubtitleQuery query) async {
    final uri = Uri.parse('$baseUrl/sub/search').replace(queryParameters: {
      'q': query.title,
      'cnt': '20',
      if (query.season != null) 'season': '${query.season}',
      if (query.episode != null) 'episode': '${query.episode}',
    });
    final data = await _getJson(uri);
    final sub = data['sub'];
    if (sub is! Map) return const [];
    final subs = sub['subs'];
    if (subs is! List) return const [];
    final result = <SubtitleCandidate>[];
    for (final item in subs) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! num) continue;
      final name = '${item['native_name'] ?? item['videoname'] ?? ''}';
      final language = '${item['language'] ?? item['lang'] ?? 'unknown'}';
      final subtype = '${item['subtype'] ?? 'srt'}';
      final url = item['download_url'] ?? item['url'];
      result.add(SubtitleCandidate(
        provider: id.toString(),
        id: id.toString(),
        title: name,
        language: language,
        format: subtype.toLowerCase(),
        downloadUrl: url is String ? url : null,
        score: item['vote_score'] is num
            ? (item['vote_score'] as num).toInt()
            : 0,
      ));
    }
    return result;
  }

  @override
  Future<List<int>> download(SubtitleCandidate candidate) async {
    var url = candidate.downloadUrl;
    if (url == null || url.isEmpty) {
      final detail = await _getJson(
        Uri.parse('$baseUrl/sub/detail').replace(
          queryParameters: {'id': candidate.id},
        ),
      );
      final sub = detail['sub'];
      if (sub is Map && sub['subs'] is List && (sub['subs'] as List).isNotEmpty) {
        final item = (sub['subs'] as List).first;
        if (item is Map) {
          final found = item['download_url'] ?? item['url'];
          if (found is String) url = found;
        }
      }
    }
    if (url == null || url.isEmpty) {
      throw const SubtitleException('ASSRT 没有返回下载地址');
    }
    final response = await _client.get(Uri.parse(url), headers: _headers);
    if (response.statusCode >= 400) {
      throw SubtitleException('ASSRT 字幕 HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers);
    } on Exception catch (error) {
      throw SubtitleException('ASSRT 请求失败：$error');
    }
    if (response.statusCode >= 400) {
      throw SubtitleException('ASSRT HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const SubtitleException('ASSRT 返回非对象 JSON');
    return decoded.cast<String, dynamic>();
  }

  void close() => _client.close();
}
