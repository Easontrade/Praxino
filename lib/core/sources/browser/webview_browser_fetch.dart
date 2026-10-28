import 'dart:async';

import 'package:webview_windows/webview_windows.dart';

import 'browser_fetch.dart';

/// [BrowserFetch] backed by the WebView2 engine that the app already ships.
///
/// One controller is reused for every request and requests are serialised: a
/// WebView can only show one page at a time, and creating a controller per
/// source would spawn dozens of browser processes. The body is read from
/// `document.body.innerText`, which is also what a JSON response renders as.
class WebViewBrowserFetch implements BrowserFetch {
  WebViewBrowserFetch({
    WebviewController? controller,
    this.timeout = const Duration(seconds: 6),
  }) : controller = controller ?? WebviewController();

  final WebviewController controller;
  final Duration timeout;

  Future<void> _tail = Future<void>.value();
  int _requestCount = 0;
  int _budget = 12;

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
      final loaded = Completer<void>();
      final subscription = controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted && !loaded.isCompleted) {
          loaded.complete();
        }
      });
      try {
        await controller.loadUrl(url);
        await loaded.future.timeout(timeout);
        final deadline = DateTime.now().add(timeout);
        while (true) {
          final text = await _bodyText();
          if (looksLikePayload(text)) return text;
          // A challenge page keeps rewriting itself; give it until the budget
          // runs out before handing back whatever is on screen.
          if (DateTime.now().isAfter(deadline)) return text;
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      } finally {
        await subscription.cancel();
      }
    } catch (_) {
      return null;
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
