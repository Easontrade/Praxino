import '../source_adapter.dart';
import 'webdav_client.dart';

/// A WebDAV/OpenList directory exposed as a source.
class WebDavAdapter implements SourceAdapter {
  WebDavAdapter({
    required this.name,
    required this.client,
  });

  @override
  final String name;
  final WebDavClient client;

  @override
  String get id => 'webdav:$name';

  @override
  Future<List<MediaSummary>> search(String keyword) async {
    final entries = await client.list('/');
    final query = keyword.trim().toLowerCase();
    return [
      for (final entry in entries)
        if (!entry.isDirectory &&
            isVideoName(entry.name) &&
            (query.isEmpty || entry.name.toLowerCase().contains(query)))
          MediaSummary(
            sourceId: id,
            title: entry.name,
            url: entry.path,
          ),
    ];
  }

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async {
    final parent = _parent(media.url);
    final entries = await client.list(parent);
    final episodes = <Episode>[
      for (final entry in entries)
        if (!entry.isDirectory && isVideoName(entry.name))
          Episode(name: entry.name, url: entry.path),
    ];
    return [EpisodeGroup(name: parent, episodes: episodes)];
  }

  @override
  Future<PlayableStream?> resolve(Episode episode) async {
    if (!isVideoName(episode.url)) return null;
    return PlayableStream(
      client.uriFor(episode.url).toString(),
      headers: client.headers,
    );
  }

  static bool isVideoName(String value) {
    final lower = value.toLowerCase();
    return _extensions.any(lower.endsWith);
  }

  static String _parent(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }

  static const _extensions = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.m4v',
    '.webm',
    '.flv',
    '.ts',
    '.wmv',
  ];
}
