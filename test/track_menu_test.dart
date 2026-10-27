import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/ui/track_menu.dart';

void main() {
  testWidgets('shows tracks and reports selections', (tester) async {
    String? audio;
    String? subtitle;
    String? secondary;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TrackMenu(
          audio: const [
            TrackOption(id: 'a1', label: '日语'),
            TrackOption(id: 'a2', label: '国语'),
          ],
          subtitles: const [
            TrackOption(id: 's1', label: '中文'),
            TrackOption(id: 's2', label: 'English'),
          ],
          selectedAudio: 'a1',
          selectedSubtitle: 's1',
          selectedSecondary: 's2',
          onAudio: (id) => audio = id,
          onSubtitle: (id) => subtitle = id,
          onSecondary: (id) => secondary = id,
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.audiotrack_outlined));
    await tester.pumpAndSettle();
    expect(find.text('音轨'), findsOneWidget);
    expect(find.text('字幕'), findsOneWidget);
    expect(find.text('第二字幕'), findsOneWidget);

    await tester.tap(find.text('国语'));
    await tester.pumpAndSettle();
    expect(audio, 'a2');
    // The dialog stays open so several tracks can be picked in one go.
    expect(find.text('音轨'), findsOneWidget);

    await tester.tap(find.text('关闭字幕'));
    await tester.pumpAndSettle();
    expect(subtitle, isNull);

    await tester.scrollUntilVisible(
      find.text('English').at(1),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('English').at(1));
    await tester.pumpAndSettle();
    expect(secondary, 's2');

    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    expect(find.text('音轨'), findsNothing);
  });

  testWidgets('is disabled when there are no tracks', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TrackMenu(
          audio: [],
          subtitles: [],
          selectedAudio: null,
          selectedSubtitle: null,
          selectedSecondary: null,
          onAudio: _ignoreAudio,
          onSubtitle: _ignoreSubtitle,
          onSecondary: _ignoreSubtitle,
        ),
      ),
    ));

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });
}

void _ignoreAudio(String _) {}
void _ignoreSubtitle(String? _) {}
