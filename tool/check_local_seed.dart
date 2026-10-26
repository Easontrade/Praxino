import 'dart:io';

import 'package:praxino/core/storage/local_seed.dart';

/// Local smoke check: loads the AppData seed and parses every rule.
///
/// This does not fetch any site; it only proves the local rule library maps
/// onto the adapter model.
Future<void> main() async {
  final seedPath = LocalSeed.defaultPath;
  stdout.writeln('seed: $seedPath');
  final subscriptions = await LocalSeed.read();
  if (subscriptions.isEmpty) {
    stdout.writeln('no subscriptions found');
    exitCode = 1;
    return;
  }
  for (final subscription in subscriptions) {
    final adapters = subscription.toAdapters();
    stdout.writeln(
      '${subscription.name}: ${subscription.rules.length} rules, '
      '${adapters.length} adapters',
    );
    for (final adapter in adapters) {
      stdout.writeln('  ${adapter.id}');
    }
  }
}
