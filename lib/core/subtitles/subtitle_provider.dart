/// A subtitle search hit from an online provider.
class SubtitleCandidate {
  const SubtitleCandidate({
    required this.provider,
    required this.id,
    required this.title,
    required this.language,
    required this.format,
    this.downloadUrl,
    this.score = 0,
    this.extra = const {},
  });

  final String provider;
  final String id;
  final String title;
  final String language;

  /// `srt`, `ass`, etc.
  final String format;
  final String? downloadUrl;
  final int score;
  final Map<String, Object?> extra;
}

class SubtitleQuery {
  const SubtitleQuery({
    required this.title,
    this.season,
    this.episode,
    this.language,
  });

  final String title;
  final int? season;
  final int? episode;
  final String? language;
}

class SubtitleException implements Exception {
  const SubtitleException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class SubtitleProvider {
  String get id;
  String get name;

  Future<List<SubtitleCandidate>> search(SubtitleQuery query);

  /// Downloads the subtitle bytes; the candidate's [SubtitleCandidate.format]
  /// names the extension.
  Future<List<int>> download(SubtitleCandidate candidate);
}
