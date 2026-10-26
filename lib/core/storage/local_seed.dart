import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../sources/subscription.dart';

/// Optional local seed for first run, read from the user's AppData.
///
/// It is never committed: this is how a developer preloads their own rule
/// library without baking sources into the repository.
class LocalSeed {
  LocalSeed._();

  static String get defaultPath {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return '';
    return p.join(appData, 'Praxino', 'seed-subscriptions.json');
  }

  static Future<List<SourceSubscription>> read({String? path}) async {
    final target = path ?? defaultPath;
    if (target.isEmpty) return const [];
    final file = File(target);
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      final raw = decoded is List
          ? decoded
          : decoded is Map && decoded['subscriptions'] is List
              ? decoded['subscriptions']
              : decoded is Map
                  ? [decoded]
                  : null;
      if (raw is! List) return const [];
      final result = <SourceSubscription>[];
      for (final item in raw) {
        final subscription = SourceSubscription.tryFromJson(item);
        if (subscription != null) result.add(subscription);
      }
      return result;
    } on FormatException {
      return const [];
    }
  }
}
