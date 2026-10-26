/// The contract every online video source implements.
///
/// Praxino ships no sources of its own. Users subscribe to source repositories
/// (Kazumi rules, TVBox configs, Stremio addons, scripts, yt-dlp), and each
/// format gets an adapter that maps it onto these few types. The UI only ever
/// talks to [SourceAdapter], so adding a new format never touches the player.
library;

/// One search hit.
class MediaSummary {
  const MediaSummary({
    required this.sourceId,
    required this.title,
    required this.url,
    this.cover,
  });

  /// [SourceAdapter.id] of the adapter that produced this item.
  final String sourceId;
  final String title;

  /// Adapter-specific locator for the detail page (absolute URL or id).
  final String url;
  final String? cover;

  @override
  String toString() => 'MediaSummary($title, $url)';
}

/// A line of episodes ("线路"). Many sites mirror the same show on several.
class EpisodeGroup {
  const EpisodeGroup({required this.name, required this.episodes});

  final String name;
  final List<Episode> episodes;
}

class Episode {
  const Episode({required this.name, required this.url});

  final String name;

  /// Adapter-specific locator for the episode's play page or stream.
  final String url;
}

/// Something mpv can open directly.
///
/// The optional quality fields are what the source reports about this stream;
/// they let the UI prefer a high-resolution or high-bitrate candidate and show
/// which subtitle languages the stream already carries.
class PlayableStream {
  const PlayableStream(
    this.url, {
    this.headers = const {},
    this.width,
    this.height,
    this.bitrateKbps,
    this.subtitleLanguages = const [],
    this.subtitleUrls = const {},
    this.audioUrl,
  });

  final String url;
  final Map<String, String> headers;
  final int? width;
  final int? height;

  /// Average bitrate in kbit/s, when the source reports it.
  final int? bitrateKbps;

  /// Language tags/labels the stream carries, e.g. `zh-Hans`, `en`.
  final List<String> subtitleLanguages;

  /// Language tag to subtitle URL, ordered with Chinese first when available.
  final Map<String, String> subtitleUrls;

  /// Separate audio URL when the source only offers video-only + audio-only
  /// formats; the player attaches it as mpv's `audio-files`.
  final String? audioUrl;

  /// Human-readable quality label for menus and logs.
  String get qualityLabel {
    if (height != null) return '${height}p';
    if (bitrateKbps != null) return '${bitrateKbps}kbps';
    return '未知';
  }
}

abstract interface class SourceAdapter {
  /// Stable id, unique across all installed sources.
  String get id;

  /// Display name.
  String get name;

  Future<List<MediaSummary>> search(String keyword);

  Future<List<EpisodeGroup>> episodes(MediaSummary media);

  /// Turns an [Episode] into a stream. Sources whose play pages hide the
  /// stream behind JavaScript return `null`, and the caller falls back to a
  /// [StreamSniffer].
  Future<PlayableStream?> resolve(Episode episode);
}

/// Finds the real video URL by loading a play page and watching its network
/// requests (the approach Kazumi uses with a WebView).
abstract interface class StreamSniffer {
  Future<PlayableStream?> sniff(String pageUrl, {Map<String, String>? headers});
}
