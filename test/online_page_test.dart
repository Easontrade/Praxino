import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/sources/source_adapter.dart';
import 'package:praxino/ui/online_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdapter implements SourceAdapter {
  @override
  String get id => 'fake';

  @override
  String get name => 'fake-source';

  @override
  Future<List<MediaSummary>> search(String keyword) async => const [
        MediaSummary(
          sourceId: 'fake',
          title: '示例剧',
          url: 'https://example.test/show',
        ),
      ];

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async => const [
        EpisodeGroup(
          name: '线路 1',
          episodes: [Episode(name: '第1集', url: 'https://example.test/1')],
        ),
      ];

  @override
  Future<PlayableStream?> resolve(Episode episode) async => null;
}

void main() {
  testWidgets('searches injected adapters and opens the episode list',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();

    await tester.pumpWidget(MaterialApp(
      home: OnlinePage(settings: store, adapters: [_FakeAdapter()]),
    ));

    await tester.enterText(find.byType(TextField), '示例');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('示例剧'), findsOneWidget);
    expect(find.text('fake-source'), findsOneWidget);

    await tester.tap(find.text('示例剧'));
    await tester.pumpAndSettle();

    expect(find.text('线路 1'), findsOneWidget);
    expect(find.text('第1集'), findsOneWidget);
  });
}
