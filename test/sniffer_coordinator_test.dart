import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/sniffer/sniffer_coordinator.dart';
import 'package:praxino/core/sources/sniffer/stream_url_matcher.dart';

class _FakeBackend implements SnifferBackend {
  final StreamController<CapturedRequest> _controller =
      StreamController<CapturedRequest>();
  String? started;
  int stopped = 0;

  @override
  Stream<CapturedRequest> get requests => _controller.stream;

  @override
  Future<void> start(String pageUrl) async => started = pageUrl;

  @override
  Future<void> stop() async {
    stopped++;
    await _controller.close();
  }

  void add(CapturedRequest request) => _controller.add(request);
}

void main() {
  test('returns the first playable request and stops the backend', () async {
    final backend = _FakeBackend();
    final sniffer = SnifferCoordinator(
      backend: backend,
      timeout: const Duration(seconds: 1),
    );

    final future = sniffer.sniff('https://example.test/play');
    backend.add(const CapturedRequest(url: 'https://example.test/page.html'));
    backend.add(const CapturedRequest(
      url: 'https://example.test/video.m3u8',
      headers: {'Referer': 'https://example.test/'},
    ));

    final stream = await future;
    expect(stream!.url, 'https://example.test/video.m3u8');
    expect(stream.headers['Referer'], 'https://example.test/');
    expect(backend.started, 'https://example.test/play');
    expect(backend.stopped, 1);
  });

  test('times out and still stops the backend', () async {
    final backend = _FakeBackend();
    final sniffer = SnifferCoordinator(
      backend: backend,
      timeout: const Duration(milliseconds: 20),
    );

    expect(await sniffer.sniff('https://example.test/play'), isNull);
    expect(backend.stopped, 1);
  });

  test('merges caller headers under captured headers', () async {
    final backend = _FakeBackend();
    final sniffer = SnifferCoordinator(
      backend: backend,
      timeout: const Duration(seconds: 1),
    );

    final future = sniffer.sniff(
      'https://example.test/play',
      headers: {'User-Agent': 'Praxino', 'Referer': 'default'},
    );
    backend.add(const CapturedRequest(
      url: 'https://example.test/a.mp4',
      headers: {'Referer': 'captured'},
    ));

    final stream = await future;
    expect(stream!.headers['User-Agent'], 'Praxino');
    expect(stream.headers['Referer'], 'captured');
  });
}
