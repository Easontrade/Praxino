import 'dart:io';

import 'package:praxino/core/storage/local_seed.dart';

/// Headless compatibility check: queries every local rule's search endpoint.
///
/// It only prints counts/errors and never resolves a stream or opens a player.
Future<void> main(List<String> args) async {
  final query = args.isNotEmpty ? args[0] : '测试';
  final subscriptions = await LocalSeed.read();
  final adapters = [
    for (final subscription in subscriptions) ...subscription.toAdapters(),
  ];
  stdout.writeln('query: $query, adapters: ${adapters.length}');
  for (final adapter in adapters) {
    try {
      final hits = await adapter
          .search(query)
          .timeout(const Duration(seconds: 10));
      stdout.writeln('${adapter.id}: ${hits.length} hits');
    } catch (error) {
      stdout.writeln('${adapter.id}: ERROR $error');
    }
  }
}
