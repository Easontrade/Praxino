import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/sources/extra_source.dart';
import 'package:praxino/ui/extra_sources_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('lists, toggles and deletes extra sources', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    await settings.saveExtraSources(const [
      ExtraSource(
        id: 's1',
        name: 'Stremio Demo',
        type: ExtraSourceType.stremio,
        location: 'https://example.test',
      ),
      ExtraSource(
        id: 'q1',
        name: 'Script Demo',
        type: ExtraSourceType.script,
        location: 'function search() {}',
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: ExtraSourcesPage(settings: settings),
    ));
    expect(find.text('Stremio Demo'), findsOneWidget);
    expect(find.text('Script Demo'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(settings.extraSources.first.enabled, isFalse);

    await tester.tap(find.byTooltip('删除').last);
    await tester.pumpAndSettle();
    expect(find.text('Script Demo'), findsNothing);
    expect(settings.extraSources, hasLength(1));
  });
}
