/// One timed line produced by speech recognition.
///
/// [id] is the alignment key used by translation: a translation result maps an
/// id back to exactly one segment, so segments are never merged or split.
class TranscriptSegment {
  const TranscriptSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
  });

  final int id;
  final Duration start;
  final Duration end;
  final String text;

  Map<String, Object?> toJson() => {
        'id': id,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
        'text': text,
      };

  static TranscriptSegment? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    if (id is! num || text is! String) return null;
    final start = raw['startMs'];
    final end = raw['endMs'];
    final startMs = start is num ? start.toInt() : null;
    final endMs = end is num ? end.toInt() : null;
    if (startMs == null || endMs == null) return null;
    return TranscriptSegment(
      id: id.toInt(),
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
      text: text,
    );
  }

  static List<TranscriptSegment> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map(TranscriptSegment.tryFromJson)
        .whereType<TranscriptSegment>()
        .toList();
  }

  @override
  String toString() => 'TranscriptSegment(#$id ${start.inMilliseconds}-'
      '${end.inMilliseconds}ms $text)';
}
