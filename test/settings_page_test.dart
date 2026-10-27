import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/subtitles/ai/claude_translator.dart';
import 'package:praxino/core/subtitles/ai/transcriber.dart';
import 'package:praxino/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('lists the keybindings with their current chords', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();

    await tester.pumpWidget(MaterialApp(home: SettingsPage(settings: store)));

    await tester.scrollUntilVisible(find.text('播放器快捷键'), 300);
    expect(find.text('播放器快捷键'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('超分辨率：关闭'), 300);
    expect(find.text('超分辨率：关闭'), findsOneWidget);
    expect(find.text('ctrl+0'), findsOneWidget);
  });

  testWidgets('saves the AI subtitle settings from the dialog', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();

    await tester.pumpWidget(MaterialApp(home: SettingsPage(settings: store)));

    await tester.scrollUntilVisible(find.text('AI 双语字幕'), 300);
    await tester.tap(find.text('AI 双语字幕'));
    await tester.pumpAndSettle();

    expect(find.text('Claude API Key'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Whisper 可执行文件'),
      r'C:\Tools\whisper\whisper-cli.exe',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Whisper 模型'),
      r'C:\Tools\whisper\ggml-large-v3-turbo.bin',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Claude API Key'),
      'local-only-key',
    );

    await tester.tap(find.text('whisper.cpp（-m / -f / -oj）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('faster-whisper（--output_format json）').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final saved = store.aiSubtitles;
    expect(saved.whisperExecutable, r'C:\Tools\whisper\whisper-cli.exe');
    expect(saved.whisperModel, r'C:\Tools\whisper\ggml-large-v3-turbo.bin');
    expect(saved.whisperFlavor, WhisperFlavor.fasterWhisper);
    expect(saved.claudeApiKey, 'local-only-key');
    expect(saved.claudeModel, ClaudeModels.haiku);
    expect(find.text('已保存 AI 双语字幕设置'), findsOneWidget);
  });
}
