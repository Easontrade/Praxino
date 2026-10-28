import 'dart:async';
import 'dart:convert';

import 'package:webview_windows/webview_windows.dart';

import 'browser_fetch.dart';

/// [BrowserFetch] backed by the WebView2 engine that the app already ships.
///
/// One controller is reused for every request and requests are serialised: a
/// WebView can only show one page at a time, and creating a controller per
/// source would spawn dozens of browser processes.
///
/// Many blocked endpoints do not reject the request itself, they answer with an
/// anti-bot interstitial and expect the *next* request to carry the cookies the
/// page just set. So the flow is: open the origin (which lets the challenge run
/// and solve), then call the API from inside that page with `fetch`, which
/// reuses the browser's cookies and TLS session. Jumping straight to the API
/// URL is kept as a fallback.
class WebViewBrowserFetch implements BrowserFetch {
  WebViewBrowserFetch({
    WebviewController? controller,
    this.timeout = const Duration(seconds: 8),
    this.settle = const Duration(milliseconds: 1200),
  }) : controller = controller ?? WebviewController();

  final WebviewController controller;
  final Duration timeout;

  /// Time given to a challenge page to finish before the API is called.
  final Duration settle;

  Future<void> _tail = Future<void>.value();
  int _requestCount = 0;
  int _budget = 12;
  String? _origin;

  /// How many browser requests were issued; used to cap a single search.
  int get requestCount => _requestCount;

  /// Only requests that already failed the cheap path land here, and a single
  /// WebView serves them one at a time. Without a budget a search with many
  /// blocked sources would keep the spinner alive for minutes, so each search
  /// gets a fixed number of browser attempts.
  void resetBudget([int requests = 12]) => _budget = requests;

  @override
  Future<String?> fetch(String url) {
    if (_budget <= 0) return Future<String?>.value(null);
    _budget--;
    _requestCount++;
    final result = _tail.then((_) => _fetch(url));
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String?> _fetch(String url) async {
    try {
      if (!controller.value.isInitialized) {
        await controller.initialize();
      }
      final origin = _originOf(url);
      if (origin != null && origin != _origin) {
        await _navigate(origin);
        _origin = origin;
        if (settle > Duration.zero) await Future<void>.delayed(settle);
      }

      final viaFetch = await _fetchInsidePage(url);
      if (viaFetch != null && looksLikePayload(viaFetch)) return viaFetch;

      // Fallback: some deployments answer the API URL directly.
      await _navigate(url);
      final deadline = DateTime.now().add(timeout);
      while (true) {
        final text = await _bodyText();
        if (looksLikePayload(text)) return text;
        if (DateTime.now().isAfter(deadline)) return text;
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    } catch (_) {
      return null;
    }
  }

  /// Runs `fetch` inside the already-loaded page and collects the body over the
  /// web-message channel (executeScript cannot await a promise).
  Future<String?> _fetchInsidePage(String url) async {
    final completer = Completer<String?>();
    final subscription = controller.webMessage.listen((message) {
      if (message is! String || completer.isCompleted) return;
      try {
        final decoded = jsonDecode(message);
        if (decoded is! Map || decoded['praxinoFetch'] != url) return;
        final body = decoded['body'];
        completer.complete(body is String ? body : null);
      } on FormatException {
        // Not ours.
      }
    });
    try {
      final encoded = jsonEncode(url);
      await controller.executeScript('''
(function () {
  try {
    fetch($encoded, {credentials: 'include'})
      .then(function (r) { return r.text(); })
      .then(function (t) {
        window.chrome.webview.postMessage(JSON.stringify({praxinoFetch: $encoded, body: t}));
      })
      .catch(function (e) {
        window.chrome.webview.postMessage(JSON.stringify({praxinoFetch: $encoded, error: String(e)}));
      });
  } catch (e) {
    window.chrome.webview.postMessage(JSON.stringify({praxinoFetch: $encoded, error: String(e)}));
  }
})();
''');
      return await completer.future.timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _navigate(String url) async {
    final loaded = Completer<void>();
    final subscription = controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted && !loaded.isCompleted) {
        loaded.complete();
      }
    });
    try {
      await controller.loadUrl(url);
      await loaded.future.timeout(timeout);
    } finally {
      await subscription.cancel();
    }
  }

  Future<String?> _bodyText() async {
    try {
      final raw = await controller.executeScript(
        'document.body ? document.body.innerText : ""',
      );
      return raw is String ? raw : null;
    } catch (_) {
      return null;
    }
  }

  static String? _originOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return '${uri.scheme}://${uri.host}/';
  }

  /// JSON or CMS XML — anything that is not the challenge page's HTML.
  static bool looksLikePayload(String? text) {
    if (text == null) return false;
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) return true;
    final lower = trimmed.toLowerCase();
    return lower.startsWith('<rss') ||
        lower.startsWith('<?xml') ||
        lower.contains('<list>') ||
        lower.contains('<video>');
  }

  Future<void> dispose() async {
    try {
      await controller.dispose();
    } catch (_) {
      // Already torn down.
    }
  }
}
