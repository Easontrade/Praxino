import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/enhance_settings.dart';
import 'package:praxino/ui/enhance_menu.dart';

void main() {
  testWidgets('opens a dialog, applies changes and stays open', (tester) async {
    final settings = ValueNotifier(const EnhanceSettings());
    addTearDown(settings.dispose);
    EnhanceSettings? changed;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EnhanceButton(
          settings: settings,
          onChanged: (value) {
            changed = value;
            settings.value = value;
          },
        ),
      ),
    ));

    await tester.tap(find.byTooltip('画质增强 (Ctrl+0~3)'));
    await tester.pumpAndSettle();
    expect(find.text('画质增强'), findsOneWidget);

    await tester.tap(find.text('Anime4K 流畅'));
    await tester.pumpAndSettle();
    expect(changed?.upscale, UpscalePreset.anime4kFast);
    // The dialog must not close after one selection.
    expect(find.text('画质增强'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('轻度降噪'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('轻度降噪'));
    await tester.pumpAndSettle();
    expect(changed?.denoise, isTrue);

    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    expect(find.text('画质增强'), findsNothing);
  });
}
