import 'dart:convert';

/// One saved playback position for a local file.
class WatchPoint {
  const WatchPoint({
    required this.path,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String path;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  /// Do not offer to resume in the first 10s or the last 30s of a file.
  static const resumeAfter = Duration(seconds: 10);
  static const keepBeforeEnd = Duration(seconds: 30);

  bool get shouldResume =>
      position > resumeAfter && duration - position > keepBeforeEnd;

  Map<String, Object?> toJson() => {
        'path': path,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static WatchPoint? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    final position = json['positionMs'];
    final duration = json['durationMs'];
    final updatedAt = json['updatedAt'];
    if (path is! String || path.isEmpty) return null;
    if (position is! num || duration is! num || updatedAt is! String) {
      return null;
    }
    final time = DateTime.tryParse(updatedAt);
    if (time == null) return null;
    return WatchPoint(
      path: path,
      position: Duration(milliseconds: position.toInt()),
      duration: Duration(milliseconds: duration.toInt()),
      updatedAt: time,
    );
  }
}

/// Resume points for local files, most recently watched first.
class WatchHistory {
  WatchHistory({
    Iterable<WatchPoint> entries = const [],
    this.maxEntries = 500,
  }) {
    for (final entry in entries) {
      _entries[entry.path] = entry;
    }
    _trim();
  }

  factory WatchHistory.fromJson(String? raw) {
    if (raw == null) return WatchHistory();
    try {
      final data = jsonDecode(raw);
      if (data is! List) return WatchHistory();
      return WatchHistory(
        entries: data.map(WatchPoint.tryFromJson).whereType<WatchPoint>(),
      );
    } on FormatException {
      return WatchHistory();
    }
  }

  final int maxEntries;
  final Map<String, WatchPoint> _entries = {};

  int get length => _entries.length;

  WatchPoint? find(String path) => _entries[path];

  /// Most recently watched first.
  List<WatchPoint> get entries {
    final list = _entries.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  void record(WatchPoint point) {
    _entries[point.path] = point;
    _trim();
  }

  void remove(String path) => _entries.remove(path);

  String toJson() => jsonEncode(entries.map((e) => e.toJson()).toList());

  void _trim() {
    if (_entries.length <= maxEntries) return;
    final oldestFirst = _entries.values.toList()
      ..sort((a, b) {
        final byTime = a.updatedAt.compareTo(b.updatedAt);
        return byTime != 0 ? byTime : a.path.compareTo(b.path);
      });
    for (final entry in oldestFirst.take(_entries.length - maxEntries)) {
      _entries.remove(entry.path);
    }
  }
}
