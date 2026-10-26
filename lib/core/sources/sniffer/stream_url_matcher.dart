import '../source_adapter.dart';

/// A network request captured from a play page's WebView.
class CapturedRequest {
  const CapturedRequest({required this.url, this.headers = const {}});

  final String url;
  final Map<String, String> headers;
}

final RegExp _streamPath =
    RegExp(r'\.(m3u8|mp4|m4v|flv|ts)$', caseSensitive: false);

/// Whether [url] looks like a playable media request (not an HTML page).
bool isStreamUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return _streamPath.hasMatch(uri.path);
}

/// First playable request in capture order, with its headers, or null.
///
/// This is the pure part of the WebView sniffer: it can be unit-tested
/// without a browser.
PlayableStream? firstStream(Iterable<CapturedRequest> requests) {
  for (final request in requests) {
    if (isStreamUrl(request.url)) {
      return PlayableStream(request.url, headers: request.headers);
    }
  }
  return null;
}
