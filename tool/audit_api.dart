// Audits the TVBox search contract against every configured site: does
// `ac=list&wd=` answer, does `ac=detail&wd=` answer with more, and does our
// `vod_play_url` parser agree with the raw payload?
//
//   dart run tool/audit_api.dart "美国精神病人"
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:praxino/core/sources/tvbox/tvbox_adapter.dart';
import 'package:praxino/core/sources/tvbox/tvbox_config.dart';

const _chrome =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? '美国精神病人' : args.first;
  final appData = Platform.environment['APPDATA'];
  if (appData == null) return;
  final sites = await TvBoxConfigLoader.loadDirectory(
    Directory(p.join(appData, 'Praxino', 'tvbox')),
  );
  final client = http.Client();
  final trustAll = IOClient(
    HttpClient()..badCertificateCallback = (_, _, _) => true,
  );
  stdout.writeln('sites=${sites.length} query=$query');

  final rows = <_Row>[];
  await _pool(sites, 8, (site) async {
    final list = await _ask(client, site, 'list', query);
    final loose = list.error == null && list.count > 0
        ? list
        : await _ask(trustAll, site, 'list', query);
    final detail = await _ask(client, site, 'detail', query);
    rows.add(_Row(site: site, list: list, detail: detail, loose: loose));
  });

  var listOk = 0;
  var detailOnly = 0;
  var bothZero = 0;
  var errors = 0;
  for (final row in rows) {
    if (row.list.count > 0) {
      listOk++;
    } else if (row.detail.count > 0) {
      detailOnly++;
    } else if (row.list.error != null || row.detail.error != null) {
      errors++;
    } else {
      bothZero++;
    }
  }
  stdout.writeln('ac=list has hits: $listOk');
  stdout.writeln('only ac=detail has hits: $detailOnly');
  stdout.writeln('both empty (no error): $bothZero');
  stdout.writeln('errors: $errors');

  final kinds = <String, int>{};
  for (final row in rows.where((r) => r.list.count == 0)) {
    final kind = _classify(row.list);
    kinds[kind] = (kinds[kind] ?? 0) + 1;
  }
  stdout.writeln('--- why the rest failed ---');
  for (final entry in kinds.entries) {
    stdout.writeln('  ${entry.key}: ${entry.value}');
  }

  stdout.writeln('--- per site (empty or error) ---');
  for (final row in rows.where((r) => r.list.count == 0)) {
    stdout.writeln(
      '${row.site.name.padRight(18)} '
      'list=${row.list.count} detail=${row.detail.count} '
      'err=${row.list.error ?? '-'} head=${row.list.head ?? '-'}',
    );
  }

  stdout.writeln('--- sites where ac=detail beats ac=list ---');
  for (final row in rows.where(
    (r) => r.list.count == 0 && r.detail.count > 0,
  )) {
    stdout.writeln(
      '  ${row.site.name}: list=${row.list.count} '
      'detail=${row.detail.count}',
    );
  }

  stdout.writeln('--- sample play_url parsing ---');
  for (final row in rows.where((r) => r.list.count > 0).take(5)) {
    final id = row.list.firstId;
    if (id == null) continue;
    final raw = await _playUrl(client, row.site, id);
    if (raw == null) continue;
    final parsed = TvBoxAdapter.parsePlayUrl(raw);
    final episodes = parsed.fold(
      0,
      (sum, group) => sum + group.episodes.length,
    );
    stdout.writeln(
      '${row.site.name}: groups=${parsed.length} '
      'episodes=$episodes',
    );
    stdout.writeln(
      '  raw: ${raw.length > 120 ? '${raw.substring(0, 120)}…' : raw}',
    );
    if (parsed.isNotEmpty && parsed.first.episodes.isNotEmpty) {
      stdout.writeln(
        '  parsed[0]: ${parsed.first.episodes.first.name} -> '
        '${parsed.first.episodes.first.url}',
      );
    }
  }
  client.close();
}

String _classify(_Answer answer) {
  final error = answer.error?.toLowerCase() ?? '';
  if (error.contains('handshake')) return 'TLS handshake rejected (anti-bot)';
  if (error.contains('connection closed')) {
    return 'connection closed (anti-bot)';
  }
  if (error.contains('timeout')) return 'timeout';
  if (error.contains('http 4')) return 'HTTP 4xx';
  if (error.isNotEmpty) return 'other network error';
  final head = answer.head ?? '';
  if (head.isEmpty) return 'empty body';
  if (head.contains('暂不支持搜索')) return 'API does not support search';
  if (head.contains('forbids keyword search')) return 'API forbids search';
  if (head.contains('<!DOCTYPE') || head.contains('<html')) {
    return 'HTML / anti-bot page instead of JSON';
  }
  if (head.startsWith('{')) return 'API answered: 0 results';
  return 'unclassified';
}

class _Row {
  _Row({
    required this.site,
    required this.list,
    required this.detail,
    required this.loose,
  });

  final TvBoxSite site;
  final _Answer list;
  final _Answer detail;
  final _Answer loose;
}

class _Answer {
  const _Answer({required this.count, this.error, this.firstId, this.head});

  final int count;
  final String? error;
  final String? firstId;
  final String? head;
}

Future<_Answer> _ask(
  http.Client client,
  TvBoxSite site,
  String ac,
  String query,
) async {
  final base = Uri.parse(site.api);
  final uri = base.replace(
    queryParameters: {...base.queryParameters, 'ac': ac, 'wd': query},
  );
  try {
    final response = await client
        .get(uri, headers: {'User-Agent': _chrome, 'Accept': '*/*'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode >= 400) {
      return _Answer(count: 0, error: 'HTTP ${response.statusCode}');
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final items = _items(text);
    final head = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _Answer(
      count: items.length,
      firstId: items.isEmpty ? null : items.first,
      head: head.length > 70 ? head.substring(0, 70) : head,
    );
  } catch (error) {
    final text = '$error'.split('\n').first;
    return _Answer(
      count: 0,
      error: text.length > 70 ? text.substring(0, 70) : text,
    );
  }
}

/// Pulls the id of every item from a JSON or XML answer.
List<String> _items(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(text);
      final list = decoded is Map ? decoded['list'] : null;
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map && item['vod_id'] != null) '${item['vod_id']}',
      ];
    } on FormatException {
      return const [];
    }
  }
  final ids = RegExp(r'<id>\s*([^<]+?)\s*</id>').allMatches(text);
  return [for (final match in ids) match.group(1)!];
}

Future<String?> _playUrl(http.Client client, TvBoxSite site, String id) async {
  final base = Uri.parse(site.api);
  final uri = base.replace(
    queryParameters: {...base.queryParameters, 'ac': 'detail', 'ids': id},
  );
  try {
    final response = await client
        .get(uri, headers: {'User-Agent': _chrome, 'Accept': '*/*'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode >= 400) return null;
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.trimLeft().startsWith('{')) {
      final decoded = jsonDecode(text);
      final list = decoded is Map ? decoded['list'] : null;
      if (list is List && list.isNotEmpty && list.first is Map) {
        return '${(list.first as Map)['vod_play_url'] ?? ''}';
      }
      return null;
    }
    final match = RegExp(r'<vod_play_url>([\s\S]*?)</vod_play_url>')
        .firstMatch(text);
    return match?.group(1);
  } catch (_) {
    return null;
  }
}

Future<void> _pool<T>(
  List<T> items,
  int limit,
  Future<void> Function(T item) body,
) async {
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= items.length) return;
      await body(items[index]);
    }
  }

  await Future.wait(
    List.generate(items.length < limit ? limit : items.length, (_) => worker()),
  );
}
