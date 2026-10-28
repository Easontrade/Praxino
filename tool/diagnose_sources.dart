// End-to-end check of the local source library: does a given title actually
// play, and where does it break? Runs the same steps as the ranking list
// (search -> episodes -> resolve -> read the stream out of the play page ->
// fetch the playlist -> fetch the first segment) but never opens a player.
//
//   dart run tool/diagnose_sources.dart "美国精神病人"
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:praxino/core/sources/source_adapter.dart';
import 'package:praxino/core/sources/source_report.dart';
import 'package:praxino/core/sources/source_report_runner.dart';
import 'package:praxino/core/sources/tvbox/tvbox_adapter.dart';
import 'package:praxino/core/sources/tvbox/tvbox_config.dart';
import 'package:praxino/core/storage/local_seed.dart';

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? '美国精神病人' : args.first;
  final client = http.Client();
  final adapters = await _adapters(client);
  stdout.writeln('sources=${adapters.length} query=$query');

  final inputs = <SourceReportInput>[];
  final failed = <String>[];
  await _pool(adapters, 8, (adapter) async {
    try {
      final hits = await adapter
          .search(query)
          .timeout(const Duration(seconds: 15));
      if (hits.isNotEmpty) inputs.add(SourceReportInput(adapter: adapter, items: hits));
    } catch (error) {
      failed.add('${adapter.name}: ${_short(error)}');
    }
  });
  stdout.writeln('hit sources=${inputs.length} dead sources=${failed.length}');

  final runner = SourceReportRunner(
    query: query,
    inputs: inputs,
    httpClient: client,
    concurrency: 6,
  );
  await runner.run();
  runner.close();

  final entries = [...runner.entries];
  SourceReport.sort(entries);
  var playable = 0;
  for (final entry in entries) {
    final check = await _verify(entry, client, runner);
    if (check.startsWith('OK')) playable++;
    final label = check.startsWith('OK') ? '能播' : '不能播';
    stdout.writeln('$label | ${entry.sourceName} | ${entry.title} | '
        '${entry.quality} | ${entry.stream?.url ?? entry.link} | $check');
  }
  stdout.writeln('---');
  stdout.writeln('playable=$playable of ${entries.length}');
  if (failed.isNotEmpty) {
    stdout.writeln('dead: ${failed.take(10).join(' / ')}');
  }
}

Future<List<SourceAdapter>> _adapters(http.Client client) async {
  final adapters = <SourceAdapter>[];
  for (final subscription in await LocalSeed.read()) {
    adapters.addAll(subscription.toAdapters(client: client));
  }
  final appData = Platform.environment['APPDATA'];
  if (appData != null && appData.isNotEmpty) {
    final sites = await TvBoxConfigLoader.loadDirectory(
      Directory(p.join(appData, 'Praxino', 'tvbox')),
    );
    for (final site in sites) {
      if (!site.searchable) continue;
      adapters.add(TvBoxAdapter(
        api: site.api,
        displayName: site.name,
        client: client,
      ));
    }
  }
  return adapters;
}

/// Follows the link mpv would actually get and proves it can start.
Future<String> _verify(
  SourceReportEntry entry,
  http.Client client,
  SourceReportRunner runner,
) async {
  final stream = entry.stream;
  if (stream == null || SourceReport.looksLikeLandingPage(stream.url)) {
    final page = stream?.url ?? entry.link;
    final extracted = await runner.streamFromPage(page);
    if (extracted == null) return 'page has no m3u8/mp4';
    return _follow(extracted, client);
  }
  return _follow(stream, client);
}

Future<String> _follow(PlayableStream stream, http.Client client) async {
  try {
    final response = await client.get(
      Uri.parse(stream.url),
      headers: {...stream.headers, 'Range': 'bytes=0-65535'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode >= 400) return 'HTTP ${response.statusCode}';
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (!body.contains('#EXTM3U')) {
      final type = response.headers['content-type'] ?? 'no content-type';
      return 'not a playlist ($type)';
    }
    var base = Uri.parse(stream.url);
    var playlist = body;
    var uri = base;
    // Master playlist -> first variant, then take its first segment.
    for (var level = 0; level < 2; level++) {
      final first = _firstLine(playlist);
      if (first == null) return 'playlist has no entries';
      uri = base.resolve(first);
      if (!uri.path.toLowerCase().endsWith('.m3u8')) return 'OK segment=$uri';
      final next = await client.get(
        uri,
        headers: {...stream.headers, 'Range': 'bytes=0-65535'},
      ).timeout(const Duration(seconds: 10));
      if (next.statusCode >= 400) return 'variant HTTP ${next.statusCode}';
      base = uri;
      playlist = utf8.decode(next.bodyBytes, allowMalformed: true);
    }
    final segment = _firstLine(playlist);
    if (segment == null) return 'variant has no segments';
    final segmentUri = base.resolve(segment);
    final head = await client.get(
      segmentUri,
      headers: {...stream.headers, 'Range': 'bytes=0-1023'},
    ).timeout(const Duration(seconds: 10));
    if (head.statusCode >= 400) return 'segment HTTP ${head.statusCode}';
    return 'OK segment=${head.statusCode}';
  } catch (error) {
    return _short(error);
  }
}

String? _firstLine(String playlist) {
  for (final line in playlist.split('\n')) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('#')) continue;
    return text;
  }
  return null;
}

/// Runs [body] over [items] with at most [limit] in flight.
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

  await Future.wait(List.generate(items.length < limit ? items.length : limit,
      (_) => worker()));
}

String _short(Object error) {
  final text = '$error'.split('\n').first.trim();
  return text.length > 90 ? '${text.substring(0, 90)}…' : text;
}
