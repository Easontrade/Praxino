import 'dart:io';

import 'package:flutter/services.dart';

/// Receives command lines forwarded by a second app instance.
///
/// The Windows runner sends newline-separated UTF-8 arguments through
/// `praxino/single_instance`; only Windows has a native side.
class SingleInstance {
  SingleInstance._();

  static const MethodChannel _channel =
      MethodChannel('praxino/single_instance');

  /// Newline-separated UTF-8 payload to arguments, dropping empty entries.
  static List<String> parsePayload(String payload) => payload
      .split('\n')
      .map((argument) => argument.trim())
      .where((argument) => argument.isNotEmpty)
      .toList();

  static void listen(void Function(List<String> arguments) onArguments) {
    if (!Platform.isWindows) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        onArguments(parsePayload(call.arguments as String));
      }
      return null;
    });
  }

  static void stop() {
    if (Platform.isWindows) _channel.setMethodCallHandler(null);
  }
}
