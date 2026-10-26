import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/reliability/source_prober.dart';
import 'package:praxino/core/sources/source_adapter.dart';

PlayableStream _stream(String url) => PlayableStream(url);

void main() {
  test('ranks reachable streams by latency', () async {
    final prober = SourceProber(
      probe: (stream) async => ProbeResult(
        url: stream.url,
        reachable: true,
        latency: stream.url.endsWith('slow')
            ? const Duration(milliseconds: 200)
            : const Duration(milliseconds: 20),
      ),
    );
    final streams = [_stream('slow'), _stream('fast')];

    final results = await prober.probeAll(streams);
    final ranked = SourceProber.rank(streams, results);

    expect(ranked.map((s) => s.url), ['fast', 'slow']);
  });

  test('a throwing probe becomes unreachable without failing the batch',
      () async {
    final prober = SourceProber(
      probe: (stream) async {
        if (stream.url == 'bad') throw StateError('boom');
        return ProbeResult(url: stream.url, reachable: true);
      },
    );
    final streams = [_stream('bad'), _stream('good')];

    final results = await prober.probeAll(streams);
    final ranked = SourceProber.rank(streams, results);

    expect(results.firstWhere((r) => r.url == 'bad').reachable, isFalse);
    expect(ranked.first.url, 'good');
  });

  test('a hanging probe times out and does not block others', () async {
    final prober = SourceProber(
      timeout: const Duration(milliseconds: 20),
      probe: (stream) async {
        if (stream.url == 'hang') {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        return ProbeResult(url: stream.url, reachable: true);
      },
    );
    final streams = [_stream('hang'), _stream('ok')];

    final watch = Stopwatch()..start();
    final results = await prober.probeAll(streams);
    watch.stop();

    expect(results.firstWhere((r) => r.url == 'hang').reachable, isFalse);
    expect(results.firstWhere((r) => r.url == 'ok').reachable, isTrue);
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });

  test('probe receives the stream headers', () async {
    final prober = SourceProber(
      probe: (stream) async {
        expect(stream.headers['Referer'], 'https://example.test/');
        return ProbeResult(url: stream.url, reachable: true);
      },
    );

    await prober.probeAll([
      const PlayableStream(
        'https://example.test/a.m3u8',
        headers: {'Referer': 'https://example.test/'},
      ),
    ]);
  });
}
