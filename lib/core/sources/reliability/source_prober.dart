import 'dart:async';

import '../source_adapter.dart';

/// Result of a lightweight reachability probe for one stream.
class ProbeResult {
  const ProbeResult({
    required this.url,
    required this.reachable,
    this.latency,
    this.error,
  });

  final String url;
  final bool reachable;
  final Duration? latency;
  final Object? error;
}

/// The network part is injected so the ranking logic is testable.
typedef StreamProbe = Future<ProbeResult> Function(PlayableStream stream);

/// Probes candidate streams concurrently and ranks them by reachability and
/// time-to-first-byte. A probe that throws or times out just becomes an
/// unreachable candidate.
class SourceProber {
  SourceProber({
    required this.probe,
    this.timeout = const Duration(seconds: 5),
  });

  final StreamProbe probe;
  final Duration timeout;

  Future<List<ProbeResult>> probeAll(Iterable<PlayableStream> streams) =>
      Future.wait(streams.map(_probeOne));

  Future<ProbeResult> _probeOne(PlayableStream stream) async {
    try {
      return await probe(stream).timeout(timeout);
    } on TimeoutException catch (error) {
      return ProbeResult(url: stream.url, reachable: false, error: error);
    } catch (error) {
      return ProbeResult(url: stream.url, reachable: false, error: error);
    }
  }

  /// Reachable streams first, fastest first; unreachable ones keep the order
  /// they came in so the caller can still show them as a last resort.
  static List<PlayableStream> rank(
    List<PlayableStream> streams,
    List<ProbeResult> results,
  ) {
    final byUrl = {for (final result in results) result.url: result};
    final ranked = [...streams];
    ranked.sort((a, b) {
      final ra = byUrl[a.url];
      final rb = byUrl[b.url];
      if (ra == null || rb == null) return 0;
      if (ra.reachable != rb.reachable) return ra.reachable ? -1 : 1;
      final la = ra.latency;
      final lb = rb.latency;
      if (la != null && lb != null) return la.compareTo(lb);
      if (la != null) return -1;
      if (lb != null) return 1;
      return 0;
    });
    return ranked;
  }
}
