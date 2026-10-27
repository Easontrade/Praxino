import '../sources/source_adapter.dart';

/// Result states shown in the source ranking.
enum SourceReportStatus { reachable, unresolved, unreachable }

/// One source/title row after resolving its first episode and probing the
/// stream. Pure data so sorting and quality labels are testable.
class SourceReportEntry {
  const SourceReportEntry({
    required this.sourceName,
    required this.title,
    required this.link,
    required this.status,
    required this.quality,
    required this.matchScore,
    this.latency,
    this.detail = '',
    this.stream,
    this.adapter,
    this.media,
    this.episode,
  });

  final String sourceName;
  final String title;
  final String link;
  final SourceReportStatus status;
  final String quality;
  final double matchScore;
  final Duration? latency;
  final String detail;

  /// Playback context: direct stream when resolved, otherwise the source and
  /// media so the UI can open the detail page and let the sniffer find it.
  final PlayableStream? stream;
  final SourceAdapter? adapter;
  final MediaSummary? media;
  final Episode? episode;

  String get statusLabel => switch (status) {
        SourceReportStatus.reachable => '可播放',
        SourceReportStatus.unresolved => '需抓流',
        SourceReportStatus.unreachable => '连接失败',
      };
}

/// One source and the search hits it returned.
class SourceReportInput {
  const SourceReportInput({required this.adapter, required this.items});

  final SourceAdapter adapter;
  final List<MediaSummary> items;
}

/// Pure helpers shared by the ranking page and its tests.
class SourceReport {
  SourceReport._();

  /// Picks the best quality label from the adapter metadata, the title/URL and
  /// an HLS master playlist (when available).
  static String qualityOf({
    int? height,
    int? width,
    String? title,
    String? url,
    String? hlsResolution,
  }) {
    if (height != null && height > 0) return '${height}p';
    final fromHls = _resolutionHeight(hlsResolution);
    if (fromHls != null) return '${fromHls}p';
    final text = '${title ?? ''} ${url ?? ''} $hlsResolution'.toLowerCase();
    if (RegExp(r'2160|3840x2160|\b4k\b').hasMatch(text)) return '4K';
    if (RegExp(r'1080|1920x1080').hasMatch(text)) return '1080p';
    if (RegExp(r'720|1280x720').hasMatch(text)) return '720p';
    if (RegExp(r'480|854x480').hasMatch(text)) return '480p';
    if (width != null && width > 0) return '宽度 ${width}px';
    return '未知';
  }

  /// 4K > 1080p > 720p > 480p > unknown, for stable ranking.
  static int qualityRank(String quality) {
    if (quality.contains('4K') || quality.contains('2160')) return 5;
    if (quality.contains('1080')) return 4;
    if (quality.contains('720')) return 3;
    if (quality.contains('480')) return 2;
    if (quality == '未知') return 0;
    return 1;
  }

  static int statusRank(SourceReportStatus status) => switch (status) {
        SourceReportStatus.reachable => 0,
        SourceReportStatus.unresolved => 1,
        SourceReportStatus.unreachable => 2,
      };

  /// The entry the "play best source" button should use: first direct stream,
  /// otherwise the first row that can open its detail page and sniff.
  static SourceReportEntry? bestEntry(List<SourceReportEntry> entries) {
    for (final entry in entries) {
      final stream = entry.stream;
      if (stream != null && !looksLikeLandingPage(stream.url)) {
        return entry;
      }
    }
    for (final entry in entries) {
      if (entry.adapter != null && entry.media != null) return entry;
    }
    return null;
  }

  /// A `/play/...` or `.html` URL is a player page, not a media stream; mpv
  /// cannot open it directly, so the report marks it as needing the sniffer.
  static bool looksLikeLandingPage(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.html') ||
        path.contains('/play/') ||
        path.contains('/vodplay/') ||
        path.contains('/detail/');
  }

  /// Playable first, then higher quality, faster probe, better title match.
  static void sort(List<SourceReportEntry> entries) {
    entries.sort((a, b) {
      final byStatus =
          statusRank(a.status).compareTo(statusRank(b.status));
      if (byStatus != 0) return byStatus;
      final byQuality =
          qualityRank(b.quality).compareTo(qualityRank(a.quality));
      if (byQuality != 0) return byQuality;
      final la = a.latency;
      final lb = b.latency;
      if (la != null && lb != null) {
        final byLatency = la.compareTo(lb);
        if (byLatency != 0) return byLatency;
      } else if (la != null) {
        return -1;
      } else if (lb != null) {
        return 1;
      }
      return b.matchScore.compareTo(a.matchScore);
    });
  }

  static int? _resolutionHeight(String? resolution) {
    if (resolution == null) return null;
    final match = RegExp(r'(\d{2,4})x(\d{2,4})').firstMatch(resolution);
    if (match == null) return null;
    return int.tryParse(match.group(2)!);
  }
}
