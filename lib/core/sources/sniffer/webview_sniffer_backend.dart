import 'dart:async';
import 'dart:convert';

import 'package:webview_windows/webview_windows.dart';

import 'sniffer_coordinator.dart';
import 'stream_url_matcher.dart';

/// WebView2 backend for [SnifferCoordinator].
///
/// The page is loaded in a hidden `Webview`; a document-start script reports
/// fetch/XHR URLs through `window.chrome.webview.postMessage`, and after
/// navigation the backend also scans `performance` resource entries.
class WebViewSnifferBackend implements SnifferBackend {
  WebViewSnifferBackend({WebviewController? controller})
      : controller = controller ?? WebviewController();

  final WebviewController controller;
  final StreamController<CapturedRequest> _requests =
      StreamController<CapturedRequest>.broadcast();

  StreamSubscription<dynamic>? _messageSub;
  StreamSubscription<LoadingState>? _loadingSub;
  bool _started = false;
  bool _stopped = false;

  @override
  Stream<CapturedRequest> get requests => _requests.stream;

  @override
  Future<void> start(String pageUrl) async {
    if (!controller.value.isInitialized) {
      await controller.initialize();
    }
    _messageSub ??= controller.webMessage.listen(_onMessage);
    _loadingSub ??=
        controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted) {
        unawaited(_scanPerformance());
      }
    });
    await controller.addScriptToExecuteOnDocumentCreated(_hookScript);
    await controller.loadUrl(pageUrl);
    _started = true;
  }

  Future<void> _scanPerformance() async {
    if (!_started) return;
    try {
      final raw = await controller.executeScript(
        'JSON.stringify(performance.getEntriesByType("resource").map(e => e.name))',
      );
      if (raw is! String) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final entry in decoded) {
        if (entry is String) {
          final request = parseWebMessage(entry);
          if (request != null) _requests.add(request);
        }
      }
    } catch (_) {
      // The page may navigate away while the script runs; ignore.
    }
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    final request = parseWebMessage(message);
    if (request != null) _requests.add(request);
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _started = false;
    await _messageSub?.cancel();
    await _loadingSub?.cancel();
    _messageSub = null;
    _loadingSub = null;
    if (!_requests.isClosed) await _requests.close();
    await controller.dispose();
  }
}

/// Parses either a JSON `{url, headers}` message or a bare URL.
CapturedRequest? parseWebMessage(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      final url = decoded['url'];
      if (url is String && isStreamUrl(url)) {
        final headers = <String, String>{};
        final rawHeaders = decoded['headers'];
        if (rawHeaders is Map) {
          for (final entry in rawHeaders.entries) {
            if (entry.value is String) {
              headers['${entry.key}'] = entry.value as String;
            }
          }
        }
        return CapturedRequest(url: url, headers: headers);
      }
    }
  } on FormatException {
    // Not JSON; fall through to the bare-URL case.
  }
  return isStreamUrl(text) ? CapturedRequest(url: text) : null;
}

const String _hookScript = r'''
(() => {
  if (window.__praxinoHooked) return;
  window.__praxinoHooked = true;
  const post = (url, headers) => {
    try {
      const out = {};
      if (headers) {
        if (typeof headers.forEach === 'function') {
          headers.forEach((v, k) => { out[k] = String(v); });
        } else {
          Object.keys(headers).forEach((k) => { out[k] = String(headers[k]); });
        }
      }
      window.chrome.webview.postMessage(JSON.stringify({url: String(url), headers: out}));
    } catch (_) {}
  };
  const originalFetch = window.fetch;
  window.fetch = function(input, init) {
    try {
      post(typeof input === 'string' ? input : input.url,
           init && init.headers);
    } catch (_) {}
    return originalFetch.apply(this, arguments);
  };
  const originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    try { post(url); } catch (_) {}
    return originalOpen.apply(this, arguments);
  };
})();
''';
