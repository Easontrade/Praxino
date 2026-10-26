import 'dart:io';

import 'package:praxino/core/sources/tvbox/tvbox_adapter.dart';
import 'package:praxino/core/sources/tvbox/tvbox_config.dart';

Future<void> main(List<String> args) async {
  final appData = Platform.environment['APPDATA']!;
  final sites = await TvBoxConfigLoader.loadDirectory(
    Directory('$appData\\Praxino\\tvbox'),
  );
  if (sites.isEmpty) {
    stdout.writeln('no tvbox sites');
    exitCode = 1;
    return;
  }
  final query = args.isEmpty ? '测试' : args.first;
  var found = false;
  for (final site in sites.take(15)) {
    final adapter = TvBoxAdapter(api: site.api, displayName: site.name);
    try {
      final hits = await adapter.search(query);
      stdout.writeln('${site.name}: ${hits.length} hits');
      for (final hit in hits.take(3)) {
        stdout.writeln('  ${hit.title}');
      }
      if (hits.isNotEmpty) {
        found = true;
        break;
      }
    } on Exception catch (error) {
      stdout.writeln('${site.name}: ERROR $error');
    } finally {
      adapter.close();
    }
  }
  if (!found) exitCode = 1;
}
