import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/sources/subscription.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rule = {
  'name': 'demo',
  'version': '1',
  'baseURL': 'https://example.test/',
  'searchURL': 'https://example.test/search?wd=@keyword',
  'searchList': "//ul[@class='list']/li",
  'searchName': '//a',
  'searchResult': '//a',
  'chapterRoads': "//ul[@class='road']",
  'chapterResult': '//li/a',
  'useWebview': false,
};

http.Response _json(Object? body, {int status = 200, Map<String, String>? headers}) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: headers ?? {});

void main() {
  test('builds adapters from cached rules', () {
    final subscription = SourceSubscription(
      url: 'https://example.test/rules.json',
      rules: [Map<String, Object?>.from(_rule)],
    );

    final adapters = subscription.toAdapters();
    expect(adapters.single.id, 'kazumi:demo');
    expect(adapters.single.name, 'demo');
  });

  test('fetch stores rules, name and etag', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://example.test/rules.json');
      return _json([_rule], headers: {'etag': '"v1"'});
    });

    final updated = await SubscriptionFetcher(client: client).fetch(
      const SourceSubscription(url: 'https://example.test/rules.json'),
    );

    expect(updated.rules, hasLength(1));
    expect(updated.etag, '"v1"');
    expect(updated.name, 'example.test');
    expect(updated.fetchedAt, isNotNull);
  });

  test('304 keeps the cached rules and etag', () async {
    final client = MockClient((request) async {
      expect(request.headers['If-None-Match'], '"v1"');
      return http.Response('', 304);
    });

    final updated = await SubscriptionFetcher(client: client).fetch(
      SourceSubscription(
        url: 'https://example.test/rules.json',
        etag: '"v1"',
        rules: [Map<String, Object?>.from(_rule)],
      ),
    );

    expect(updated.rules, hasLength(1));
    expect(updated.etag, '"v1"');
    expect(updated.fetchedAt, isNotNull);
  });

  test('rejects HTTP errors and malformed documents', () async {
    final failing = SubscriptionFetcher(
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    expect(
      () => failing.fetch(
          const SourceSubscription(url: 'https://example.test/rules.json')),
      throwsA(isA<SubscriptionException>()),
    );

    final empty = SubscriptionFetcher(
      client: MockClient((_) async => _json([])),
    );
    expect(
      () => empty.fetch(
          const SourceSubscription(url: 'https://example.test/rules.json')),
      throwsA(isA<SubscriptionException>()),
    );
  });

  test('subscription json round-trips and skips broken entries', () {
    final subscription = SourceSubscription(
      url: 'https://example.test/rules.json',
      name: 'demo',
      etag: '"v1"',
      fetchedAt: DateTime(2026, 1, 1),
      rules: [Map<String, Object?>.from(_rule)],
    );

    final restored = SourceSubscription.tryFromJson(subscription.toJson())!;
    expect(restored.url, subscription.url);
    expect(restored.rules.single['name'], 'demo');
    expect(SourceSubscription.tryFromJson({'name': 'no url'}), isNull);
  });

  test('SettingsStore persists subscriptions', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();
    await store.saveSubscriptions([
      SourceSubscription(
        url: 'https://example.test/rules.json',
        name: 'demo',
        rules: [Map<String, Object?>.from(_rule)],
      ),
    ]);

    expect(store.subscriptions.single.url, 'https://example.test/rules.json');
    expect(store.subscriptions.single.rules, hasLength(1));
  });

  test('pasted JSON accepts an array, a single rule or a rules wrapper', () {
    final array = SourceSubscription.fromJsonText(jsonEncode([_rule]));
    expect(array.rules.single['name'], 'demo');
    expect(array.url, startsWith('local://'));
    expect(array.toAdapters().single.id, 'kazumi:demo');

    final single = SourceSubscription.fromJsonText(jsonEncode(_rule));
    expect(single.rules.single['name'], 'demo');

    final wrapped =
        SourceSubscription.fromJsonText(jsonEncode({'rules': [_rule]}));
    expect(wrapped.rules.single['name'], 'demo');
  });

  test('pasted JSON rejects garbage and empty rule lists', () {
    expect(() => SourceSubscription.fromJsonText('not json'),
        throwsA(isA<SubscriptionException>()));
    expect(() => SourceSubscription.fromJsonText('[]'),
        throwsA(isA<SubscriptionException>()));
  });
}
