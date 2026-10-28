import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

/// Keeps the shared browser engine alive for [controller] while a page needs it.
///
/// WebView2 draws into a real window, so one has to exist even though the user
/// never sees it: the surface is parked far off-screen and never focused.
class WebViewBrowserHost extends StatelessWidget {
  const WebViewBrowserHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final WebviewController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<WebviewValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (!value.isInitialized) return const SizedBox.shrink();
            return Positioned(
              left: -10000,
              top: -10000,
              child: SizedBox(
                width: 800,
                height: 600,
                child: Webview(controller),
              ),
            );
          },
        ),
      ],
    );
  }
}
