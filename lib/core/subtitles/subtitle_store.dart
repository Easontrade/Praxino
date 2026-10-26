import 'dart:io';

import 'package:path/path.dart' as p;

/// Saves downloaded subtitles next to the video, where mpv auto-loads them.
class SubtitleStore {
  SubtitleStore._();

  static Future<File> save({
    required String videoPath,
    required List<int> bytes,
    required String language,
    required String format,
  }) async {
    final directory = Directory(p.join(p.dirname(videoPath), 'subs'));
    await directory.create(recursive: true);
    final safeLanguage = language.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeFormat = format.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final name =
        '${p.basenameWithoutExtension(videoPath)}.$safeLanguage.$safeFormat';
    final file = File(p.join(directory.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
