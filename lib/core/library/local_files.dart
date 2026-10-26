import 'dart:io';

import 'package:path/path.dart' as p;

const Set<String> kVideoExtensions = {
  '.mkv', '.mp4', '.m4v', '.avi', '.mov', '.wmv', '.flv', '.webm', '.ts',
  '.m2ts', '.mts', '.rmvb', '.rm', '.3gp', '.ogv', '.vob', '.mpg', '.mpeg',
};

const Set<String> kSubtitleExtensions = {
  '.ass', '.ssa', '.srt', '.vtt', '.sub', '.sup', '.idx',
};

bool isVideoFile(String path) =>
    kVideoExtensions.contains(p.extension(path).toLowerCase());

bool isSubtitleFile(String path) =>
    kSubtitleExtensions.contains(p.extension(path).toLowerCase());

/// The videos in [file]'s folder, in natural order, so "next episode" works
/// without a library scan.
List<String> siblingVideos(String file) {
  final dir = Directory(p.dirname(file));
  if (!dir.existsSync()) return [file];
  final videos = dir
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .where(isVideoFile)
      .toList()
    ..sort(naturalCompare);
  return videos.isEmpty ? [file] : videos;
}

final RegExp _chunk = RegExp(r'(\d+)|(\D+)');

/// Compares strings so that `EP2` sorts before `EP10`.
int naturalCompare(String a, String b) {
  final ca = _chunk.allMatches(a.toLowerCase()).toList();
  final cb = _chunk.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < ca.length && i < cb.length; i++) {
    final x = ca[i], y = cb[i];
    final int c;
    if (x.group(1) != null && y.group(1) != null) {
      c = BigInt.parse(x.group(1)!).compareTo(BigInt.parse(y.group(1)!));
    } else {
      c = x.group(0)!.compareTo(y.group(0)!);
    }
    if (c != 0) return c;
  }
  return ca.length.compareTo(cb.length);
}
