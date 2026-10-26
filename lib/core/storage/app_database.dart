import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../sources/subscription.dart';

part 'app_database.g.dart';

class SubscriptionRows extends Table {
  TextColumn get url => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime().nullable()();
  TextColumn get rulesJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {url};
}

@DriftDatabase(tables: [SubscriptionRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.defaults() {
    final base = Platform.environment['APPDATA'] ?? Directory.current.path;
    final directory = Directory(p.join(base, 'Praxino'))..createSync(recursive: true);
    return AppDatabase(
      NativeDatabase(File(p.join(directory.path, 'praxino.sqlite'))),
    );
  }

  @override
  int get schemaVersion => 1;

  Future<List<SourceSubscription>> loadSubscriptions() async {
    final rows = await select(subscriptionRows).get();
    return [
      for (final row in rows)
        SourceSubscription(
          url: row.url,
          name: row.name,
          enabled: row.enabled,
          etag: row.etag,
          fetchedAt: row.fetchedAt,
          rules: _rules(row.rulesJson),
        ),
    ];
  }

  Future<void> saveSubscriptions(List<SourceSubscription> subscriptions) async {
    await transaction(() async {
      await delete(subscriptionRows).go();
      for (final subscription in subscriptions) {
        await into(subscriptionRows).insert(
          SubscriptionRowsCompanion.insert(
            url: subscription.url,
            name: Value(subscription.name),
            enabled: Value(subscription.enabled),
            etag: Value(subscription.etag),
            fetchedAt: Value(subscription.fetchedAt),
            rulesJson: Value(jsonEncode(subscription.rules)),
          ),
        );
      }
    });
  }

  static List<Map<String, Object?>> _rules(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return [
        for (final item in data)
          if (item is Map) Map<String, Object?>.from(item),
      ];
    } on FormatException {
      return const [];
    }
  }
}

/// Drift-backed subscription storage, replacing the old shared_preferences key.
class SubscriptionRepository {
  SubscriptionRepository(this.database);

  final AppDatabase database;

  Future<List<SourceSubscription>> load() => database.loadSubscriptions();

  Future<void> save(List<SourceSubscription> subscriptions) =>
      database.saveSubscriptions(subscriptions);

  /// Copies the legacy shared_preferences list once, when the DB is empty.
  Future<void> migrateFrom(List<SourceSubscription> legacy) async {
    if (legacy.isEmpty) return;
    if ((await database.loadSubscriptions()).isEmpty) {
      await save(legacy);
    }
  }
}
