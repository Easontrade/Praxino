import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('lists the keybindings with their current chords', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();

    await tester.pumpWidget(MaterialApp(home: SettingsPage(settings: store)));

    expect(find.text('播放器快捷键'), findsOneWidget);
    expect(find.text('超分辨率：关闭'), findsOneWidget);
    expect(find.text('ctrl+0'), findsOneWidget);
  });
}
