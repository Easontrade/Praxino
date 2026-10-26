import 'dart:convert';

import '../../process/process_runner.dart';
import '../source_adapter.dart';

/// yt-dlp-backed source. A pasted URL becomes a one-item result; a keyword
/// uses yt-dlp's `ytsearch5:` search.
class YtDlpAdapter implements SourceAdapter {
  YtDlpAdapter({
    this.executable = 'yt-dlp',
    ProcessRunner? runner,
  }) : _runner = runner ?? const SystemProcessRunner();

  final String executable;
  final ProcessRunner _runner;

  @override
  String get id => 'ytdlp';

  @override
  String get name => 'yt-dlp';

  @override
  Future<List<MediaSummary>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return const [];
    if (_isUrl(query)) {
      return [MediaSummary(sourceId: id, title: query, url: query)];
    }
    final data = await _json(['-J', '--flat-playlist', 'ytsearch5:$query']);
    final entries = data['entries'];
    if (entries is! List) return const [];
    return [
      for (final entry in entries)
        if (entry is Map &&
            (entry['url'] is String || entry['webpage_url'] is String))
          MediaSummary(
            sourceId: id,
            title: '${entry['title'] ?? entry['url']}',
            url: _webpageUrl(entry),
          ),
    ];
  }

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async => [
        EpisodeGroup(
          name: media.title,
          episodes: [Episode(name: media.title, url: media.url)],
        ),
      ];

  @override
  Future<PlayableStream?> resolve(Episode episode) async {
    final data = await _json(['-J', '--no-playlist', episode.url]);
    final formats = _formats(data);
    if (formats.isEmpty) {
      throw const YtDlpException('yt-dlp 没有返回可播放格式');
    }

    final combined = _best(formats, combined: true);
    if (combined != null) return _stream(combined, data);

    final video = _best(formats, combined: false);
    final audio = _bestAudio(formats);
    if (video == null) {
      throw const YtDlpException('yt-dlp 没有返回视频轨');
    }
    return _stream(video, data, audioUrl: audio?['url'] as String?);
  }

  static bool _isUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static String _webpageUrl(Map entry) {
    final page = entry['webpage_url'];
    if (page is String && page.isNotEmpty) return page;
    final url = '${entry['url']}';
    if (url.startsWith('http')) return url;
    return 'https://www.youtube.com/watch?v=$url';
  }

  Future<Map<String, dynamic>> _json(List<String> arguments) async {
    final output = await _runner.run(executable, arguments);
    if (output.exitCode != 0) {
      final message = output.stderr.trim();
      throw YtDlpException(
          message.isEmpty ? 'yt-dlp 退出码 ${output.exitCode}' : message);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(output.stdout);
    } on FormatException {
      throw const YtDlpException('yt-dlp 输出不是 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const YtDlpException('yt-dlp 输出不是 JSON 对象');
    }
    return decoded;
  }

  static List<Map<String, dynamic>> _formats(Map<String, dynamic> data) {
    final raw = data['formats'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map<String, dynamic> && item['url'] is String) item,
    ];
  }

  static Map<String, dynamic>? _best(
    List<Map<String, dynamic>> formats, {
    required bool combined,
  }) {
    final candidates = formats.where((format) {
      final video = format['vcodec'] != 'none';
      final audio = format['acodec'] != 'none';
      return combined ? video && audio : video && !audio;
    }).toList()
      ..sort(_byQuality);
    return candidates.isEmpty ? null : candidates.last;
  }

  static Map<String, dynamic>? _bestAudio(
    List<Map<String, dynamic>> formats,
  ) {
    final candidates = formats
        .where((format) =>
            format['vcodec'] == 'none' && format['acodec'] != 'none')
        .toList()
      ..sort((a, b) => _num(a['abr'] ?? a['tbr'])
          .compareTo(_num(b['abr'] ?? b['tbr'])));
    return candidates.isEmpty ? null : candidates.last;
  }

  static int _byQuality(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byHeight = _num(a['height']).compareTo(_num(b['height']));
    if (byHeight != 0) return byHeight;
    return _num(a['tbr']).compareTo(_num(b['tbr']));
  }

  static double _num(Object? value) =>
      value is num ? value.toDouble() : 0;

  static PlayableStream _stream(
    Map<String, dynamic> format,
    Map<String, dynamic> data, {
    String? audioUrl,
  }) {
    final headers = <String, String>{};
    final rawHeaders = format['http_headers'] ?? data['http_headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.value is String) headers['${entry.key}'] = entry.value as String;
      }
    }
    final subtitles = data['subtitles'];
    return PlayableStream(
      format['url'] as String,
      headers: headers,
      width: format['width'] is num ? (format['width'] as num).toInt() : null,
      height:
          format['height'] is num ? (format['height'] as num).toInt() : null,
      bitrateKbps: format['tbr'] is num
          ? (format['tbr'] as num).round()
          : null,
      subtitleLanguages:
          subtitles is Map ? subtitles.keys.map((key) => '$key').toList() : const [],
      audioUrl: audioUrl,
    );
  }
}

class YtDlpException implements Exception {
  const YtDlpException(this.message);

  final String message;

  @override
  String toString() => message;
}
