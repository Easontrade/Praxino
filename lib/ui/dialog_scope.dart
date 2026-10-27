import 'package:flutter/widgets.dart';

/// Owns the [TextEditingController]s of a dialog and disposes them when the
/// dialog route is really removed.
///
/// `showDialog` completes as soon as the route is popped, but the route keeps
/// rebuilding during its exit animation. Disposing the controllers at that
/// point throws "A TextEditingController was used after being disposed" (the
/// integration test in `integration_test/app_test.dart` caught this).
class DialogScope extends StatefulWidget {
  const DialogScope({
    super.key,
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<DialogScope> createState() => _DialogScopeState();
}

class _DialogScopeState extends State<DialogScope> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
