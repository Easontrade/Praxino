import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/sources/reliability/http_stream_prober.dart';
import 'package:praxino/core/sources/source_adapter.dart';

void main() {
  test('accepts partial content and sends a range request', () async {
    final prober = HttpStreamProber(
      client: MockClient((request) async {
        expect(request.headers['Range'], 'bytes=0-0');
        expect(request.headers['Referer'], 'https://example.test/');
        return http.Response('', 206);
      }),
    );

    final result = await prober.probe(const PlayableStream(
      'https://example.test/a.m3u8',
      headers: {'Referer': 'https://example.test/'},
    ));

    expect(result.reachable, isTrue);
    expect(result.latency, isNotNull);
    prober.close();
  });

  test('accepts 416 as a reachable stream', () async {
    final prober = HttpStreamProber(
      client: MockClient((_) async => http.Response('', 416)),
    );
    final result = await prober.probe(
      const PlayableStream('https://example.test/a.mp4'),
    );
    expect(result.reachable, isTrue);
    prober.close();
  });

  test('marks HTTP errors and exceptions unreachable', () async {
    final failing = HttpStreamProber(
      client: MockClient((_) async => http.Response('', 500)),
    );
    expect(
      (await failing.probe(const PlayableStream('https://example.test/a')))
          .reachable,
      isFalse,
    );
    failing.close();

    final throwing = HttpStreamProber(
      client: MockClient((_) async => throw StateError('network')),
    );
    final result = await throwing.probe(
      const PlayableStream('https://example.test/a'),
    );
    expect(result.reachable, isFalse);
    expect(result.error, isA<StateError>());
    throwing.close();
  });
}
