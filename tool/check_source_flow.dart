import 'dart:io';

import 'package:praxino/core/storage/local_seed.dart';
import 'package:praxino/core/sources/source_adapter.dart';

/// Searches one local rule, then fetches the first hit's episodes and tries
/// to resolve the first episode. Prints metadata only; never opens a player.
Future<void> main(List<String> args) async {
  final subscriptions = await LocalSeed.read();
  final adapters = <SourceAdapter>[
    for (final subscription in subscriptions) ...subscription.toAdapters(),
  ];
  if (adapters.isEmpty) {
    stdout.writeln('no adapters');
    exitCode = 1;
    return;
  }
  final id = args.isNotEmpty ? args[0] : adapters.first.id;
  final query = args.length > 1 ? args[1] : '测试';
  final adapter = adapters.firstWhere((candidate) => candidate.id == id);

  final hits = await adapter
      .search(query)
      .timeout(const Duration(seconds: 30));
  stdout.writeln('search: ${hits.length} hits');
  if (hits.isEmpty) return;
  final hit = hits.first;
  stdout.writeln('first: ${hit.title} (${hit.url})');

  final groups = await adapter
      .episodes(hit)
      .timeout(const Duration(seconds: 30));
  stdout.writeln('groups: ${groups.length}');
  for (final group in groups.take(3)) {
    stdout.writeln('  ${group.name}: ${group.episodes.length} episodes');
    for (final episode in group.episodes.take(3)) {
      stdout.writeln('    ${episode.name} -> ${episode.url}');
    }
  }
  if (groups.isEmpty || groups.first.episodes.isEmpty) return;

  final stream = await adapter
      .resolve(groups.first.episodes.first)
      .timeout(const Duration(seconds: 30));
  if (stream == null) {
    stdout.writeln('resolve: null (WebView/StreamSniffer required)');
  } else {
    stdout.writeln('resolve: ${stream.url} quality=${stream.qualityLabel} '
        'headers=${stream.headers.keys.toList()}');
  }
}
