import 'dart:async';

import 'source_adapter.dart';

/// One source's answer to a search, including its error (if any).
///
/// The registry never throws for a single source: a timeout or a broken
/// adapter only marks this result, so one bad source cannot hide the others.
class SourceSearchResult {
  const SourceSearchResult({
    required this.sourceId,
    required this.sourceName,
    this.items = const [],
    this.error,
  });

  final String sourceId;
  final String sourceName;
  final List<MediaSummary> items;
  final Object? error;

  bool get hasError => error != null;
}

/// Holds the user's enabled adapters and searches them concurrently.
///
/// The registry contains no sources of its own; adapters are added from the
/// user's subscriptions at runtime.
class SourceRegistry {
  SourceRegistry({
    Iterable<SourceAdapter> sources = const [],
    this.timeout = const Duration(seconds: 10),
  }) : _sources = [...sources];

  final List<SourceAdapter> _sources;

  /// Per-source search budget. A slow source is reported as an error instead
  /// of delaying the others.
  final Duration timeout;

  List<SourceAdapter> get sources => List.unmodifiable(_sources);

  /// Adds [adapter], replacing an existing adapter with the same id.
  void add(SourceAdapter adapter) {
    _sources.removeWhere((source) => source.id == adapter.id);
    _sources.add(adapter);
  }

  bool remove(String sourceId) {
    final before = _sources.length;
    _sources.removeWhere((source) => source.id == sourceId);
    return _sources.length != before;
  }

  /// Emits one result per source as soon as it finishes.
  Stream<SourceSearchResult> search(String keyword) {
    if (_sources.isEmpty) return const Stream.empty();
    final adapters = List<SourceAdapter>.of(_sources);
    late final StreamController<SourceSearchResult> controller;
    var remaining = adapters.length;
    controller = StreamController<SourceSearchResult>(
      onListen: () {
        for (final adapter in adapters) {
          _searchOne(adapter, keyword).then((result) {
            if (controller.isClosed) return;
            controller.add(result);
            remaining--;
            if (remaining == 0) controller.close();
          });
        }
      },
    );
    return controller.stream;
  }

  /// Convenience wrapper for callers that want the whole set.
  Future<List<SourceSearchResult>> searchAll(String keyword) =>
      search(keyword).toList();

  Future<SourceSearchResult> _searchOne(
    SourceAdapter adapter,
    String keyword,
  ) async {
    try {
      final items = await adapter.search(keyword).timeout(timeout);
      return SourceSearchResult(
        sourceId: adapter.id,
        sourceName: adapter.name,
        items: items,
      );
    } on TimeoutException catch (error) {
      return SourceSearchResult(
        sourceId: adapter.id,
        sourceName: adapter.name,
        error: error,
      );
    } catch (error) {
      return SourceSearchResult(
        sourceId: adapter.id,
        sourceName: adapter.name,
        error: error,
      );
    }
  }
}
