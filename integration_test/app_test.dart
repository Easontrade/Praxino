import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:praxino/core/enhance/enhance_settings.dart';
import 'package:praxino/core/enhance/offline/offline_job.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/sources/source_adapter.dart';
import 'package:praxino/main.dart';
import 'package:praxino/ui/offline_tasks_page.dart';
import 'package:praxino/ui/online_page.dart';
import 'package:praxino/ui/player_page.dart';
import 'package:praxino/ui/settings_page.dart';
import 'package:praxino/ui/subscriptions_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end checks that drive the real widgets and plugins on Windows.
///
/// The fixture is a six-second SMPTE colour-bar clip generated with ffmpeg and
/// committed under `integration_test/fixtures/`; nothing here touches the
/// network or the user's settings (SharedPreferences is in-memory).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    MediaKit.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opens a local file in the player', (tester) async {
    final settings = await _openPlayer(tester);
    await _pumpUntil(
      tester,
      () => settings.recent.isNotEmpty,
      timeout: const Duration(seconds: 10),
      description: 'recent file to be recorded',
    );
    expect(p.equals(settings.recent.single, _videoPath()), isTrue);
    expect(find.byType(PlayerPage), findsOneWidget);
    await _disposePlayer(tester);
  });

  testWidgets('changes the enhancement preset and persists it', (tester) async {
    final settings = await _openPlayer(tester);

    // Controls start hidden (visibleOnMount is false); move the mouse over the
    // video to reveal the bottom bar, like a user would.
    final video = tester.getCenter(find.byType(PlayerPage));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: video);
    await mouse.moveTo(video);
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntil(
      tester,
      () => find.byTooltip('画质增强 (Ctrl+0~3)').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
      description: 'player controls to appear',
    );

    await tester.tap(find.byTooltip('画质增强 (Ctrl+0~3)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Anime4K 流畅'), findsOneWidget);

    await tester.tap(find.text('Anime4K 流畅'));
    await _pumpUntil(
      tester,
      () => settings.enhance.upscale == UpscalePreset.anime4kFast,
      timeout: const Duration(seconds: 15),
      description: 'enhancement preset to be saved',
    );

    final reloaded = await SettingsStore.load();
    expect(reloaded.enhance.upscale, UpscalePreset.anime4kFast);
    await _disposePlayer(tester);
  });

  testWidgets('saves dandanplay credentials from the settings page',
      (tester) async {
    final settings = await SettingsStore.load();
    await tester.pumpWidget(MaterialApp(home: SettingsPage(settings: settings)));
    await tester.pump();

    final entry = find.text('弹弹play 凭证');
    await tester.scrollUntilVisible(
      entry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'integration-app-id');
    await tester.enterText(fields.at(1), 'integration-secret');
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, '保存'),
    ));
    await _pumpUntil(
      tester,
      () => settings.dandanplayAppId == 'integration-app-id',
      timeout: const Duration(seconds: 5),
      description: 'credentials to be saved',
    );

    expect(settings.dandanplayAppId, 'integration-app-id');
    expect(settings.dandanplayAppSecret, 'integration-secret');
  });

  testWidgets('imports a subscription from pasted JSON', (tester) async {
    final settings = await SettingsStore.load();
    await tester.pumpWidget(
      MaterialApp(home: SubscriptionsPage(settings: settings)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('粘贴 JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      jsonEncode([_rule]),
    );
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await tester.pumpAndSettle();

    expect(find.text('本地规则'), findsOneWidget);
    expect(settings.subscriptions, hasLength(1));
    expect(settings.subscriptions.single.rules, hasLength(1));
  });

  testWidgets('searches an injected source and opens its episodes',
      (tester) async {
    final settings = await SettingsStore.load();
    await tester.pumpWidget(MaterialApp(
      home: OnlinePage(settings: settings, adapters: [_FakeAdapter()]),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.byTooltip('搜索'));
    await _pumpUntil(
      tester,
      () => find.text('测试番剧').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
      description: 'search results to appear',
    );

    await tester.tap(find.text('测试番剧'));
    await _pumpUntil(
      tester,
      () => find.text('第 1 集').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
      description: 'episode list to appear',
    );
    expect(find.text('线路 1'), findsOneWidget);
  });

  testWidgets('lists a queued offline job and pauses it', (tester) async {
    final settings = await SettingsStore.load();
    await settings.saveOfflineJobs([
      OfflineJob.forSource(_videoPath(), id: 'integration-job'),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: OfflineTasksPage(settings: settings)),
    );

    await _pumpUntil(
      tester,
      () => find.text('pattern.mp4').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
      description: 'offline job to load',
    );
    await tester.tap(find.byTooltip('暂停/取消'));
    await _pumpUntil(
      tester,
      () => settings.offlineJobs.single.status == OfflineJobStatus.paused,
      timeout: const Duration(seconds: 5),
      description: 'job to become paused',
    );

    expect(find.textContaining('已暂停'), findsOneWidget);
    expect(settings.offlineJobs.single.status, OfflineJobStatus.paused);
  });
}

Future<SettingsStore> _openPlayer(WidgetTester tester) async {
  final settings = await SettingsStore.load();
  await tester.pumpWidget(
    PraxinoApp(settings: settings, initialSource: _videoPath()),
  );
  await _pumpUntil(
    tester,
    () => find.byType(PlayerPage).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 20),
    description: 'player page to open',
  );
  expect(find.byType(PlayerPage), findsOneWidget);
  return settings;
}

/// Gives the player a moment to release libmpv before the next test.
Future<void> _disposePlayer(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  fail('timed out waiting for $description');
}

String _videoPath() {
  Directory directory = Directory.current;
  String? root;
  for (var depth = 0; depth < 10; depth++) {
    if (File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
      root = directory.path;
      break;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  if (root == null) {
    fail('cannot find the project root from ${Directory.current.path}');
  }
  final path =
      p.join(root, 'integration_test', 'fixtures', 'pattern.mp4');
  if (!File(path).existsSync()) {
    fail('missing integration test video: $path');
  }
  return path;
}

const _rule = {
  'name': 'demo',
  'version': '1',
  'baseURL': 'https://example.test/',
  'searchURL': 'https://example.test/search?wd=@keyword',
  'searchList': "//ul[@class='list']/li",
  'searchName': '//a',
  'searchResult': '//a',
  'chapterRoads': "//ul[@class='road']",
  'chapterResult': '//li/a',
  'useWebview': false,
};

class _FakeAdapter implements SourceAdapter {
  @override
  String get id => 'fake:integration';

  @override
  String get name => '测试源';

  @override
  Future<List<MediaSummary>> search(String keyword) async => [
        MediaSummary(sourceId: id, title: '测试番剧', url: 'show-1'),
      ];

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async => [
        EpisodeGroup(
          name: '线路 1',
          episodes: [
            Episode(name: '第 1 集', url: 'https://example.test/ep1.mp4'),
          ],
        ),
      ];

  @override
  Future<PlayableStream?> resolve(Episode episode) async =>
      PlayableStream(episode.url);
}
