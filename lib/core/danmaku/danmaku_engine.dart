import 'dart:math' as math;

enum DanmakuMode { scroll, top, bottom }

class DanmakuItem {
  const DanmakuItem({
    required this.time,
    required this.text,
    this.mode = DanmakuMode.scroll,
    this.color = 0xFFFFFFFF,
    this.fontSize = 24,
  });

  final Duration time;
  final String text;
  final DanmakuMode mode;
  final int color;
  final double fontSize;
}

class DanmakuPlacement {
  const DanmakuPlacement({
    required this.item,
    required this.x,
    required this.y,
    required this.width,
  });

  final DanmakuItem item;
  final double x;
  final double y;
  final double width;
}

/// Pure lane allocation and scroll math for one video size.
class DanmakuEngine {
  DanmakuEngine({
    this.width = 1280,
    this.height = 720,
    this.laneHeight = 34,
    this.scrollSpeed = 140,
    this.scrollDuration = const Duration(seconds: 6),
    this.fixedDuration = const Duration(seconds: 5),
    this.gap = 16,
  });

  final double width;
  final double height;
  final double laneHeight;
  final double scrollSpeed;
  final Duration scrollDuration;
  final Duration fixedDuration;
  final double gap;

  final List<_Entry> _entries = [];
  int _laneCount = 1;

  int get laneCount => _laneCount;

  void setItems(Iterable<DanmakuItem> items) {
    _entries
      ..clear()
      ..addAll(items.map(_Entry.new))
      ..sort((a, b) => a.item.time.compareTo(b.item.time));
    _layout();
  }

  List<DanmakuPlacement> placementsAt(Duration position) {
    final result = <DanmakuPlacement>[];
    for (final entry in _entries) {
      final elapsed =
          (position - entry.item.time).inMicroseconds / Duration.microsecondsPerSecond;
      if (elapsed < 0) continue;
      if (entry.item.mode == DanmakuMode.scroll) {
        if (elapsed > scrollDuration.inMilliseconds / 1000) continue;
        final x = width - elapsed * scrollSpeed;
        if (x + entry.width < 0) continue;
        result.add(DanmakuPlacement(
          item: entry.item,
          x: x,
          y: entry.y,
          width: entry.width,
        ));
      } else {
        if (elapsed > fixedDuration.inMilliseconds / 1000) continue;
        result.add(DanmakuPlacement(
          item: entry.item,
          x: (width - entry.width) / 2,
          y: entry.y,
          width: entry.width,
        ));
      }
    }
    return result;
  }

  static double measure(String text, double fontSize) {
    var width = 0.0;
    for (final rune in text.runes) {
      width += rune <= 0x7F ? fontSize * 0.55 : fontSize;
    }
    return width;
  }

  void _layout() {
    _laneCount =
        math.max(1, ((height * 0.8) / laneHeight).floor());
    final ready = List<double>.filled(_laneCount, -1e9);
    var topLane = 0;
    var bottomLane = 0;
    for (final entry in _entries) {
      entry.width = measure(entry.item.text, entry.item.fontSize);
      switch (entry.item.mode) {
        case DanmakuMode.scroll:
          var lane = 0;
          var best = double.infinity;
          final time = entry.item.time.inMicroseconds /
              Duration.microsecondsPerSecond;
          for (var i = 0; i < _laneCount; i++) {
            if (ready[i] <= time) {
              lane = i;
              break;
            }
            if (ready[i] < best) {
              best = ready[i];
              lane = i;
            }
          }
          entry.lane = lane;
          entry.y = 8 + lane * laneHeight;
          ready[lane] = time + (entry.width + gap) / scrollSpeed;
        case DanmakuMode.top:
          entry.lane = topLane;
          entry.y = 8 + topLane * laneHeight;
          topLane = (topLane + 1) % math.max(1, (_laneCount / 4).floor());
        case DanmakuMode.bottom:
          entry.lane = bottomLane;
          entry.y =
              height - (bottomLane + 1) * laneHeight - 8;
          bottomLane =
              (bottomLane + 1) % math.max(1, (_laneCount / 4).floor());
      }
    }
  }
}

class _Entry {
  _Entry(this.item);

  final DanmakuItem item;
  int lane = 0;
  double y = 0;
  double width = 0;
}
