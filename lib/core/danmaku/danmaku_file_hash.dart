import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// Dandanplay's file hash: MD5 of the first 16 MiB.
class DanmakuFileHash {
  DanmakuFileHash._();

  static const int sampleSize = 16 * 1024 * 1024;

  static Future<String> of(File file) async {
    final handle = await file.open();
    try {
      final length = await file.length();
      final bytes = await handle.read(math.min(length, sampleSize));
      return md5.convert(bytes).toString();
    } finally {
      await handle.close();
    }
  }
}
