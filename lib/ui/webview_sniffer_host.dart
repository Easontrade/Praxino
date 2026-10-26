import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../core/sources/sniffer/webview_sniffer_backend.dart';

/// Keeps a hidden WebView2 alive while [backend] sniffs a play page.
///
/// The backend starts the page from outside; this widget just gives WebView2
/// a render surface. It is parked off-screen and never receives focus.
class WebViewSnifferHost extends StatelessWidget {
  const WebViewSnifferHost({
    super.key,
    required this.backend,
    required this.child,
  });

  final WebViewSnifferBackend backend;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<WebviewValue>(
          valueListenable: backend.controller,
          builder: (context, value, _) {
            if (!value.isInitialized) return const SizedBox.shrink();
            return Positioned(
              left: -10000,
              top: -10000,
              child: SizedBox(
                width: 800,
                height: 600,
                child: Webview(backend.controller),
              ),
            );
          },
        ),
      ],
    );
  }
}
