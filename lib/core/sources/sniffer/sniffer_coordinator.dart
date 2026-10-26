import 'dart:async';

import '../source_adapter.dart';
import 'stream_url_matcher.dart';

/// The WebView side of the sniffer: start loading a page, publish requests,
/// stop (and dispose the browser) when done.
///
/// Kept as an interface so the coordinator is testable without a browser.
abstract interface class SnifferBackend {
  Future<void> start(String pageUrl);
  Future<void> stop();
  Stream<CapturedRequest> get requests;
}

/// Watches captured requests until the first playable one or a timeout.
class SnifferCoordinator implements StreamSniffer {
  SnifferCoordinator({
    required this.backend,
    this.timeout = const Duration(seconds: 15),
  });

  final SnifferBackend backend;
  final Duration timeout;

  @override
  Future<PlayableStream?> sniff(
    String pageUrl, {
    Map<String, String>? headers,
  }) async {
    await backend.start(pageUrl);
    try {
      await for (final request in backend.requests.timeout(timeout)) {
        final stream = firstStream([request]);
        if (stream != null) {
          return PlayableStream(
            stream.url,
            headers: {...?headers, ...stream.headers},
          );
        }
      }
    } on TimeoutException {
      return null;
    } finally {
      await backend.stop();
    }
    return null;
  }
}
