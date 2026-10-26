import 'dart:io';

import 'package:praxino/core/storage/local_seed.dart';
import 'package:praxino/core/sources/source_adapter.dart';

/// Runs one local subscription rule against its real search endpoint.
///
/// Usage: `dart run tool/check_source_search.dart <adapter-id> [query]`
/// This prints result counts/titles only; it does not resolve or play streams.
Future<void> main(List<String> args) async {
  final subscriptions = await LocalSeed.read();
  final adapters = <SourceAdapter>[
    for (final subscription in subscriptions) ...subscription.toAdapters(),
  ];
  if (adapters.isEmpty) {
    stdout.writeln('no adapters in the local seed');
    exitCode = 1;
    return;
  }

  final id = args.isNotEmpty ? args[0] : adapters.first.id;
  final query = args.length > 1 ? args[1] : '测试';
  final adapter = adapters.firstWhere(
    (candidate) => candidate.id == id,
    orElse: () {
      stdout.writeln('unknown adapter: $id');
      stdout.writeln('available: ${adapters.map((a) => a.id).join(', ')}');
      exitCode = 1;
      return adapters.first;
    },
  );

  stdout.writeln('adapter: ${adapter.id} (${adapter.name}), query: $query');
  try {
    final hits = await adapter.search(query).timeout(const Duration(seconds: 30));
    stdout.writeln('results: ${hits.length}');
    for (final hit in hits.take(10)) {
      stdout.writeln('  ${hit.title} -> ${hit.url}');
    }
  } catch (error) {
    stdout.writeln('search failed: $error');
    exitCode = 1;
  }
}
