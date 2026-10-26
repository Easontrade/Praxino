import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/danmaku/danmaku_engine.dart';

void main() {
  test('measures ASCII and CJK roughly', () {
    expect(DanmakuEngine.measure('abc', 20), closeTo(33, 0.1));
    expect(DanmakuEngine.measure('弹幕', 20), 40);
  });

  test('assigns separate lanes when two comments overlap', () {
    final engine = DanmakuEngine(width: 800, height: 400);
    engine.setItems(const [
      DanmakuItem(time: Duration.zero, text: '第一条弹幕很长很长很长很长'),
      DanmakuItem(time: Duration.zero, text: '第二条'),
    ]);

    final placements = engine.placementsAt(Duration.zero);
    expect(placements, hasLength(2));
    expect(placements[0].y == placements[1].y, isFalse);
  });

  test('scroll comments expire and top comments are centered', () {
    final engine = DanmakuEngine(width: 800, height: 400);
    engine.setItems(const [
      DanmakuItem(time: Duration.zero, text: '滚动'),
      DanmakuItem(
        time: Duration.zero,
        text: '顶部',
        mode: DanmakuMode.top,
      ),
    ]);

    expect(engine.placementsAt(Duration.zero), hasLength(2));
    expect(engine.placementsAt(const Duration(seconds: 7)), isEmpty);

    final top = engine.placementsAt(Duration.zero).firstWhere(
          (placement) => placement.item.mode == DanmakuMode.top,
        );
    expect(top.x, closeTo((800 - top.width) / 2, 0.1));
  });

  test('lays out a dense list without throwing', () {
    final engine = DanmakuEngine(width: 1280, height: 720);
    engine.setItems([
      for (var i = 0; i < 1000; i++)
        DanmakuItem(
          time: Duration(milliseconds: i * 60),
          text: '弹幕 $i',
        ),
    ]);
    expect(engine.placementsAt(const Duration(seconds: 30)), isNotEmpty);
  });

  test('keeps a 1000/minute frame layout well under one frame', () {
    final engine = DanmakuEngine(width: 1280, height: 720);
    engine.setItems([
      for (var i = 0; i < 1000; i++)
        DanmakuItem(
          time: Duration(milliseconds: i * 60),
          text: '弹幕 $i 这是一条比较长的滚动评论',
        ),
    ]);

    final watch = Stopwatch()..start();
    for (var frame = 0; frame < 600; frame++) {
      engine.placementsAt(Duration(milliseconds: frame * 16));
    }
    watch.stop();
    final perFrameMs = watch.elapsedMicroseconds / 600 / 1000;
    expect(perFrameMs, lessThan(8));
  });
}
