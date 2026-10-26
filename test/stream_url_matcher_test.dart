import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/sniffer/stream_url_matcher.dart';

void main() {
  test('recognizes playable extensions and ignores pages', () {
    expect(isStreamUrl('https://example.test/play/index.m3u8'), isTrue);
    expect(isStreamUrl('https://example.test/a/b.mp4?token=1'), isTrue);
    expect(isStreamUrl('https://example.test/watch/index.html'), isFalse);
    expect(isStreamUrl('https://example.test/play'), isFalse);
    expect(isStreamUrl('ftp://example.test/a.m3u8'), isFalse);
  });

  test('returns the first stream with its headers', () {
    final stream = firstStream(const [
      CapturedRequest(url: 'https://example.test/page.html'),
      CapturedRequest(
        url: 'https://example.test/video.m3u8',
        headers: {'Referer': 'https://example.test/'},
      ),
      CapturedRequest(url: 'https://example.test/other.mp4'),
    ]);

    expect(stream!.url, 'https://example.test/video.m3u8');
    expect(stream.headers['Referer'], 'https://example.test/');
  });

  test('returns null when nothing playable was captured', () {
    expect(firstStream(const []), isNull);
    expect(
      firstStream(const [
        CapturedRequest(url: 'https://example.test/page.html'),
      ]),
      isNull,
    );
  });
}
