import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/source_adapter.dart';
import 'package:praxino/core/sources/source_registry.dart';

class _FakeAdapter implements SourceAdapter {
  _FakeAdapter(
    this.id, {
    this.delay = Duration.zero,
    this.error,
    this.results = const [],
  });

  @override
  final String id;

  final Duration delay;
  final Object? error;
  final List<MediaSummary> results;

  @override
  String get name => 'source-$id';

  @override
  Future<List<MediaSummary>> search(String keyword) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return results;
  }

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async => const [];

  @override
  Future<PlayableStream?> resolve(Episode episode) async => null;
}

MediaSummary _hit(String sourceId, String title) => MediaSummary(
      sourceId: sourceId,
      title: title,
      url: 'https://example.test/$sourceId',
    );

void main() {
  test('searches every adapter and keeps per-source results', () async {
    final registry = SourceRegistry(
      sources: [
        _FakeAdapter('a', results: [_hit('a', 'A1')]),
        _FakeAdapter('b', results: [_hit('b', 'B1')]),
      ],
    );

    final results = await registry.searchAll('anything');

    expect(results, hasLength(2));
    expect(results.every((r) => !r.hasError), isTrue);
    expect(results.map((r) => r.sourceId).toSet(), {'a', 'b'});
    expect(results.firstWhere((r) => r.sourceId == 'a').items.single.title,
        'A1');
  });

  test('a broken adapter does not hide the others', () async {
    final registry = SourceRegistry(
      sources: [
        _FakeAdapter('bad', error: StateError('boom')),
        _FakeAdapter('good', results: [_hit('good', 'ok')]),
      ],
    );

    final results = await registry.searchAll('x');

    final bad = results.firstWhere((r) => r.sourceId == 'bad');
    final good = results.firstWhere((r) => r.sourceId == 'good');
    expect(bad.hasError, isTrue);
    expect(bad.error, isA<StateError>());
    expect(good.hasError, isFalse);
    expect(good.items.single.title, 'ok');
  });

  test('a slow adapter times out without delaying the rest', () async {
    final registry = SourceRegistry(
      timeout: const Duration(milliseconds: 30),
      sources: [
        _FakeAdapter('slow', delay: const Duration(seconds: 2)),
        _FakeAdapter('fast', results: [_hit('fast', 'ok')]),
      ],
    );

    final watch = Stopwatch()..start();
    final results = await registry.searchAll('x');
    watch.stop();

    final slow = results.firstWhere((r) => r.sourceId == 'slow');
    expect(slow.hasError, isTrue);
    expect(slow.error, isA<TimeoutException>());
    expect(results.firstWhere((r) => r.sourceId == 'fast').items.single.title,
        'ok');
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });

  test('adds, replaces and removes adapters by id', () async {
    final registry = SourceRegistry();
    expect(await registry.searchAll('x'), isEmpty);

    registry.add(_FakeAdapter('a', results: [_hit('a', 'old')]));
    registry.add(_FakeAdapter('a', results: [_hit('a', 'new')]));
    final afterReplace = await registry.searchAll('x');
    expect(afterReplace.single.items.single.title, 'new');

    expect(registry.remove('a'), isTrue);
    expect(registry.remove('a'), isFalse);
    expect(registry.sources, isEmpty);
  });

  test('streams results one by one and then closes', () async {
    final registry = SourceRegistry(
      sources: [
        _FakeAdapter('a', results: [_hit('a', 'A')]),
        _FakeAdapter('b', results: [_hit('b', 'B')]),
      ],
    );

    final seen = <String>[];
    await for (final result in registry.search('x')) {
      seen.add(result.sourceId);
    }

    expect(seen.toSet(), {'a', 'b'});
    expect(seen, hasLength(2));
  });
}
