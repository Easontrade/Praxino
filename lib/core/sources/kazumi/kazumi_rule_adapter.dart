import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:json_path/json_path.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import '../source_adapter.dart';
import 'kazumi_rule.dart';

const _defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';

/// Runs one [KazumiRule] as a [SourceAdapter].
class KazumiRuleAdapter implements SourceAdapter {
  KazumiRuleAdapter(this.rule, {http.Client? client})
      : _client = client ?? http.Client();

  final KazumiRule rule;
  final http.Client _client;

  @override
  String get id => 'kazumi:${rule.name}';

  @override
  String get name => rule.name;

  Map<String, String> get _headers => {
        'User-Agent':
            rule.userAgent.isEmpty ? _defaultUserAgent : rule.userAgent,
        if (rule.referer.isNotEmpty) 'Referer': rule.referer,
      };

  // ── search ────────────────────────────────────────────────────────────────

  @override
  Future<List<MediaSummary>> search(String keyword) =>
      rule.searchMode == 'api' ? _searchApi(keyword) : _searchXPath(keyword);

  Future<List<MediaSummary>> _searchXPath(String keyword) async {
    final http.Response res;
    if (rule.usePost) {
      final uri = Uri.parse(rule.searchUrl.split('?').first);
      final query = Uri.parse(rule.searchUrl).queryParameters.map(
          (k, v) => MapEntry(k, v.replaceAll('@keyword', keyword)));
      res = await _client.post(uri, headers: _headers, body: query);
    } else {
      final url = rule.searchUrl
          .replaceAll('@keyword', Uri.encodeComponent(keyword));
      res = await _client.get(Uri.parse(url), headers: _headers);
    }
    _check(res);
    final doc = html.parse(utf8.decode(res.bodyBytes)).documentElement!;
    final results = <MediaSummary>[];
    for (final item in doc.queryXPath(rule.searchList).nodes) {
      final title = item.queryXPath(rule.searchName).node?.text?.trim();
      final href =
          item.queryXPath(rule.searchResult).node?.attributes['href'];
      if (title == null || title.isEmpty || href == null) continue;
      results.add(MediaSummary(
        sourceId: id,
        title: title,
        url: _absolute(href),
      ));
    }
    return results;
  }

  Future<List<MediaSummary>> _searchApi(String keyword) async {
    final cfg = rule.searchApi!;
    final data = await _request(cfg['request'] as Map<String, dynamic>,
        {'@keyword': keyword});
    return [
      for (final item in _read(cfg['listPath'], data))
        MediaSummary(
          sourceId: id,
          title: '${_read(cfg['namePath'], item).firstOrNull ?? ''}',
          url: '${_read(cfg['sourcePath'], item).firstOrNull ?? ''}',
        ),
    ].where((m) => m.title.isNotEmpty && m.url.isNotEmpty).toList();
  }

  // ── episodes ──────────────────────────────────────────────────────────────

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) =>
      rule.chapterMode == 'api' ? _episodesApi(media) : _episodesXPath(media);

  Future<List<EpisodeGroup>> _episodesXPath(MediaSummary media) async {
    final res = await _client.get(Uri.parse(media.url), headers: _headers);
    _check(res);
    final doc = html.parse(utf8.decode(res.bodyBytes)).documentElement!;
    final groups = <EpisodeGroup>[];
    for (final road in doc.queryXPath(rule.chapterRoads).nodes) {
      final episodes = [
        for (final a in road.queryXPath(rule.chapterResult).nodes)
          if (a.attributes['href'] case final href?)
            Episode(
              name: (a.text ?? '').trim(),
              url: _absolute(href),
            ),
      ];
      if (episodes.isNotEmpty) {
        groups.add(EpisodeGroup(
            name: '线路 ${groups.length + 1}', episodes: episodes));
      }
    }
    return groups;
  }

  Future<List<EpisodeGroup>> _episodesApi(MediaSummary media) async {
    final cfg = rule.chapterApi!;
    if ((cfg['format'] ?? 'nested') != 'nested') {
      throw UnsupportedError(
          '${rule.name}: chapter format "${cfg['format']}" is not supported yet');
    }
    final data = await _request(
        cfg['request'] as Map<String, dynamic>, {'@source': media.url});
    final page = (cfg['episodePage'] as Map<String, dynamic>?)?['url']
        as String?;
    return [
      for (final road in _read(cfg['roadsPath'], data))
        EpisodeGroup(
          name: '${_read(cfg['roadNamePath'], road).firstOrNull ?? '线路'}',
          episodes: [
            for (final ep in _read(cfg['episodesPath'], road))
              () {
                final epUrl =
                    '${_read(cfg['episodeUrlPath'], ep).firstOrNull ?? ''}';
                return Episode(
                  name:
                      '${_read(cfg['episodeNamePath'], ep).firstOrNull ?? ''}',
                  url: page == null
                      ? epUrl
                      : page
                          .replaceAll('@source', media.url)
                          .replaceAll('@episodeUrl', epUrl),
                );
              }(),
          ],
        ),
    ];
  }

  // ── resolve ───────────────────────────────────────────────────────────────

  @override
  Future<PlayableStream?> resolve(Episode episode) async {
    // Kazumi play pages embed the stream behind site JavaScript; a
    // StreamSniffer has to load them.
    if (rule.useWebview) return null;
    return PlayableStream(episode.url, headers: _headers);
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  String _absolute(String href) =>
      Uri.parse(rule.baseUrl).resolve(href).toString();

  void _check(http.Response res) {
    if (res.statusCode >= 400) {
      throw http.ClientException(
          '${rule.name}: HTTP ${res.statusCode}', res.request?.url);
    }
  }

  Iterable<Object?> _read(Object? path, Object? data) =>
      path is String && path.isNotEmpty
          ? JsonPath(path).read(data).map((m) => m.value)
          : const [];

  Future<Object?> _request(
      Map<String, dynamic> req, Map<String, String> vars) async {
    String sub(String s) =>
        vars.entries.fold(s, (acc, e) => acc.replaceAll(e.key, e.value));
    Object? subAll(Object? v) => switch (v) {
          final String s => sub(s),
          final Map<String, dynamic> m =>
            m.map((k, v) => MapEntry(k, subAll(v))),
          final List<dynamic> l => l.map(subAll).toList(),
          _ => v,
        };

    final uri = Uri.parse(sub(req['url'] as String));
    final headers = {
      ..._headers,
      ...((req['headers'] as Map<String, dynamic>?) ?? {})
          .map((k, v) => MapEntry(k, sub('$v'))),
    };
    final body = subAll(req['body']);
    final http.Response res;
    if ((req['method'] as String? ?? 'GET').toUpperCase() == 'POST') {
      final isJson = (req['bodyType'] ?? 'json') == 'json';
      if (isJson) headers['Content-Type'] = 'application/json';
      res = await _client.post(uri,
          headers: headers,
          body: isJson
              ? jsonEncode(body)
              : (body as Map?)?.map((k, v) => MapEntry('$k', '$v')));
    } else {
      final query = (body as Map?)?.map((k, v) => MapEntry('$k', '$v'));
      res = await _client.get(
          query == null || query.isEmpty
              ? uri
              : uri.replace(queryParameters: {...uri.queryParameters, ...query}),
          headers: headers);
    }
    _check(res);
    return jsonDecode(utf8.decode(res.bodyBytes));
  }
}
