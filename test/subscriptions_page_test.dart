import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/sources/subscription.dart';
import 'package:praxino/core/storage/app_database.dart';
import 'package:praxino/ui/subscriptions_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows a seeded local subscription and its rule count',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SubscriptionRepository(database);
    await repository.save([
      SourceSubscription(
        url: 'local://kazumi-default',
        name: 'Kazumi 默认规则',
        rules: [
          {'name': 'demo', 'baseURL': 'https://example.test/'}
        ],
      ),
    ]);
    final settings = await SettingsStore.load(subscriptions: repository);

    await tester.pumpWidget(MaterialApp(
      home: SubscriptionsPage(settings: settings),
    ));

    expect(find.text('Kazumi 默认规则'), findsOneWidget);
    expect(find.textContaining('本地规则'), findsOneWidget);
    expect(find.textContaining('1 条'), findsOneWidget);
  });
}
