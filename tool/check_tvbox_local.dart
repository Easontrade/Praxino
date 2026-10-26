import 'dart:io';

import 'package:praxino/core/sources/tvbox/tvbox_config.dart';

Future<void> main() async {
  final appData = Platform.environment['APPDATA'];
  if (appData == null) {
    stdout.writeln('APPDATA missing');
    exitCode = 1;
    return;
  }
  final dir = Directory('$appData\\Praxino\\tvbox');
  final sites = await TvBoxConfigLoader.loadDirectory(dir);
  final jsonCount = sites.where((site) => site.type == 1).length;
  final xmlCount = sites.where((site) => site.type == 0).length;
  stdout.writeln('tvbox_dir=${dir.path}');
  stdout.writeln('sites=${sites.length} json=$jsonCount xml=$xmlCount');
  for (final site in sites.take(5)) {
    stdout.writeln('  ${site.name} -> ${site.api}');
  }
}
