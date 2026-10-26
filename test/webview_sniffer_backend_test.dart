import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/sniffer/webview_sniffer_backend.dart';

void main() {
  test('parses a bare stream URL', () {
    final request = parseWebMessage('https://example.test/video.m3u8');
    expect(request!.url, 'https://example.test/video.m3u8');
  });

  test('parses a JSON message with headers', () {
    final request = parseWebMessage(
      '{"url":"https://example.test/a.mp4","headers":{"Referer":"https://example.test/"}}',
    );
    expect(request!.url, 'https://example.test/a.mp4');
    expect(request.headers['Referer'], 'https://example.test/');
  });

  test('ignores pages and garbage', () {
    expect(parseWebMessage('https://example.test/index.html'), isNull);
    expect(parseWebMessage('not a url'), isNull);
    expect(parseWebMessage(''), isNull);
    expect(parseWebMessage('{"url":"https://example.test/page.html"}'), isNull);
  });
}
