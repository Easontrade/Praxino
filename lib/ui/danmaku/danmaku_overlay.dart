import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/danmaku/danmaku_engine.dart';

/// Paints danmaku over the video. It never takes pointer events.
class DanmakuOverlay extends StatelessWidget {
  const DanmakuOverlay({
    super.key,
    required this.position,
    required this.items,
    required this.engine,
    this.enabled = true,
  });

  final Stream<Duration> position;
  final ValueListenable<List<DanmakuItem>> items;
  final DanmakuEngine engine;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return IgnorePointer(
      child: ValueListenableBuilder<List<DanmakuItem>>(
        valueListenable: items,
        builder: (context, value, _) {
          engine.setItems(value);
          return StreamBuilder<Duration>(
            stream: position,
            initialData: Duration.zero,
            builder: (context, snapshot) => CustomPaint(
              painter: _DanmakuPainter(engine, snapshot.data ?? Duration.zero),
              size: Size.infinite,
            ),
          );
        },
      ),
    );
  }
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter(this.engine, this.position);

  final DanmakuEngine engine;
  final Duration position;

  @override
  void paint(Canvas canvas, Size size) {
    for (final placement in engine.placementsAt(position)) {
      final painter = TextPainter(
        text: TextSpan(
          text: placement.item.text,
          style: TextStyle(
            color: Color(placement.item.color),
            fontSize: placement.item.fontSize,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(1, 1)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      painter.paint(canvas, Offset(placement.x, placement.y));
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) =>
      oldDelegate.position != position || oldDelegate.engine != engine;
}
