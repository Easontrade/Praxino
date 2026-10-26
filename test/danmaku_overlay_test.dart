import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/danmaku/danmaku_engine.dart';
import 'package:praxino/ui/danmaku/danmaku_overlay.dart';

void main() {
  testWidgets('renders a non-interactive overlay layer', (tester) async {
    final items = ValueNotifier<List<DanmakuItem>>(const [
      DanmakuItem(time: Duration.zero, text: '弹幕'),
    ]);
    addTearDown(items.dispose);

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 800,
        height: 400,
        child: DanmakuOverlay(
          position: Stream.value(Duration.zero),
          items: items,
          engine: DanmakuEngine(width: 800, height: 400),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(DanmakuOverlay), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DanmakuOverlay),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
