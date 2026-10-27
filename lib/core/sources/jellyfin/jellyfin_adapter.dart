import '../source_adapter.dart';
import 'jellyfin_client.dart';

/// Jellyfin/Emby as a searchable source; UI can also browse via [JellyfinClient].
class JellyfinAdapter implements SourceAdapter {
  JellyfinAdapter({
    required this.name,
    required this.client,
  });

  @override
  final String name;
  final JellyfinClient client;

  @override
  String get id => 'jellyfin:$name';

  @override
  Future<List<MediaSummary>> search(String keyword) async {
    final items = await client.search(keyword);
    return [
      for (final item in items)
        MediaSummary(
          sourceId: id,
          title: item.displayName,
          url: '${item.type}|${item.id}',
        ),
    ];
  }

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async {
    final parts = media.url.split('|');
    if (parts.length < 2) return const [];
    final type = parts[0];
    final id = parts[1];
    if (type == 'Movie' || type == 'Episode') {
      return [
        EpisodeGroup(name: media.title, episodes: [
          Episode(name: media.title, url: media.url),
        ]),
      ];
    }
    final items = await client.items(id);
    return [
      EpisodeGroup(
        name: media.title,
        episodes: [
          for (final item in items)
            if (item.type == 'Episode' || item.type == 'Movie')
              Episode(name: item.displayName, url: '${item.type}|${item.id}'),
        ],
      ),
    ];
  }

  @override
  Future<PlayableStream?> resolve(Episode episode) async {
    final parts = episode.url.split('|');
    if (parts.length < 2) return null;
    final playback = await client.playback(JellyfinItem(
      id: parts[1],
      name: episode.name,
      type: parts[0],
    ));
    final subtitles = <String, String>{};
    for (final subtitle in playback.subtitles) {
      subtitles.putIfAbsent(subtitle.language, () => subtitle.url);
    }
    return PlayableStream(
      playback.url,
      headers: playback.headers,
      subtitleLanguages: subtitles.keys.toList(),
      subtitleUrls: subtitles,
    );
  }
}
