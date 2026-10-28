import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:praxino/core/sources/browser/webview_browser_fetch.dart';
import 'package:praxino/ui/webview_browser_host.dart';

/// Proves the browser fallback really runs: WebView2 navigates, the page body
/// is read back, and a JSON answer is recognised as a payload.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the browser engine returns a JSON body', (tester) async {
    final fetcher = WebViewBrowserFetch(timeout: const Duration(seconds: 20));
    addTearDown(fetcher.dispose);

    await tester.pumpWidget(MaterialApp(
      home: WebViewBrowserHost(
        controller: fetcher.controller,
        child: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    // Give WebView2 a moment to attach its surface before navigating.
    await tester.pump(const Duration(seconds: 1));

    final body = await tester.runAsync(
      () => fetcher.fetch('https://api.github.com/repos/flutter/flutter'),
    );

    expect(body, isNotNull, reason: 'the browser returned no body');
    expect(
      body!.trimLeft().startsWith('{'),
      isTrue,
      reason: 'expected JSON, got: $body',
    );
  });
}
