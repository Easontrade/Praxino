import 'package:path/path.dart' as p;

import '../../library/local_files.dart';
import 'webdav_client.dart';

const Set<String> _textSubtitleExtensions = {'.ass', '.ssa', '.srt', '.vtt'};

/// Folder entries first, then files in natural order, so "EP2" sorts before
/// "EP10" exactly like a local folder.
List<WebDavEntry> sortedWebDavEntries(Iterable<WebDavEntry> entries) {
  final list = entries.toList()
    ..sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      final byName = naturalCompare(a.name, b.name);
      return byName != 0 ? byName : a.path.compareTo(b.path);
    });
  return list;
}

/// Playable videos in [entries], in the same order the browser shows them.
List<WebDavEntry> webDavVideoEntries(Iterable<WebDavEntry> entries) => [
      for (final entry in sortedWebDavEntries(entries))
        if (!entry.isDirectory && isVideoFile(entry.name)) entry,
    ];

bool isWebDavVideo(WebDavEntry entry) =>
    !entry.isDirectory && isVideoFile(entry.name);

/// Video URL to subtitle URL map, in the order the player should try them
/// (Chinese before English before everything else).
///
/// Subtitle files are matched like mpv's fuzzy auto-sub: `<video>.ass`,
/// `<video>.zh.ass`, `<video>_en.srt` and so on.
Map<String, Map<String, String>> webDavSubtitleUrls(
  Iterable<WebDavEntry> entries, {
  required String Function(String path) uriFor,
}) {
  final all = entries.where((entry) => !entry.isDirectory).toList();
  final subtitles = [
    for (final entry in all)
      if (_textSubtitleExtensions.contains(p.extension(entry.name).toLowerCase()))
        entry,
  ];
  final result = <String, Map<String, String>>{};
  for (final video in all.where(isWebDavVideo)) {
    final matches = [
      for (final subtitle in subtitles)
        if (isSiblingSubtitle(subtitle.name, video.name)) subtitle,
    ]..sort((a, b) {
        final byLanguage = subtitlePriority(a.name).compareTo(
          subtitlePriority(b.name),
        );
        return byLanguage != 0 ? byLanguage : naturalCompare(a.name, b.name);
      });
    if (matches.isEmpty) continue;
    result[uriFor(video.path)] = {
      for (final subtitle in matches) subtitle.name: uriFor(subtitle.path),
    };
  }
  return result;
}

/// Whether [subtitleName] looks like a subtitle for [videoName], allowing a
/// language suffix such as `.zh` or `_en`.
bool isSiblingSubtitle(String subtitleName, String videoName) {
  if (!_textSubtitleExtensions
      .contains(p.extension(subtitleName).toLowerCase())) {
    return false;
  }
  final videoBase = p.basenameWithoutExtension(videoName).toLowerCase();
  final subtitleBase =
      p.basenameWithoutExtension(subtitleName).toLowerCase();
  if (videoBase.isEmpty || subtitleBase.isEmpty) return false;
  if (subtitleBase == videoBase) return true;
  if (!subtitleBase.startsWith(videoBase)) return false;
  return _separators.contains(subtitleBase[videoBase.length]);
}

/// Lower is preferred; Chinese subtitles come first, then English.
int subtitlePriority(String subtitleName) {
  final base = p.basenameWithoutExtension(subtitleName).toLowerCase();
  final tokens = base.split(RegExp(r'[._\-\s()\[\]]+')).toSet();
  if (tokens.any(_chineseTokens.contains) || RegExp(r'[简繁中]').hasMatch(base)) {
    return 0;
  }
  if (tokens.any(_englishTokens.contains)) return 1;
  return 2;
}

/// Stable resume key for a WebDAV file: server + path, without credentials,
/// query string or a trailing slash.
///
/// The same file must produce the same key after a token refresh or when the
/// caller adds a cache-busting query, and the key must never contain the
/// password, so it is safe to persist in `WatchHistory`.
String webDavHistoryKey(Uri uri) {
  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final normalized = Uri(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : 0,
    path: path,
  );
  return 'webdav:$normalized';
}

const _separators = {'.', '_', '-', ' '};

const _chineseTokens = {
  'zh', 'zho', 'chi', 'chs', 'cht', 'sc', 'tc', 'cn', 'zh-hans', 'zh-hant',
  'chinese', 'mandarin', '中', '中文', '简', '繁',
};

const _englishTokens = {'en', 'eng', 'english', '英', '英文'};
