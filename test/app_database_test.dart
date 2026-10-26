import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/sources/subscription.dart';
import 'package:praxino/core/storage/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('round-trips subscriptions through drift', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SubscriptionRepository(database);

    await repository.save([
      SourceSubscription(
        url: 'https://example.test/rules.json',
        name: 'demo',
        etag: '"v1"',
        rules: [
          {'name': 'demo', 'baseURL': 'https://example.test/'}
        ],
      ),
    ]);

    final loaded = await repository.load();
    expect(loaded.single.name, 'demo');
    expect(loaded.single.etag, '"v1"');
    expect(loaded.single.rules.single['name'], 'demo');
  });

  test('legacy migration only fills an empty database', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SubscriptionRepository(database);
    final legacy = [
      const SourceSubscription(url: 'local://old', name: 'legacy'),
    ];

    await repository.migrateFrom(legacy);
    expect((await repository.load()).single.url, 'local://old');

    await repository.migrateFrom([
      const SourceSubscription(url: 'local://new', name: 'new'),
    ]);
    expect((await repository.load()).single.url, 'local://old');
  });

  test('SettingsStore reads and writes through the repository', () async {
    final legacy = SourceSubscription(
      url: 'local://legacy',
      name: 'legacy',
      rules: [
        {'name': 'demo', 'baseURL': 'https://example.test/'}
      ],
    );
    SharedPreferences.setMockInitialValues({
      'subscriptions.v1': jsonEncode([legacy.toJson()]),
    });
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SubscriptionRepository(database);

    final store = await SettingsStore.load(subscriptions: repository);
    expect(store.subscriptions.single.url, 'local://legacy');

    await store.saveSubscriptions([
      const SourceSubscription(url: 'local://new', name: 'new'),
    ]);
    expect((await repository.load()).single.url, 'local://new');
  });
}
