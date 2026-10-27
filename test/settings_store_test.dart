import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/library/watch_history.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/subtitles/ai/ai_subtitle_job.dart';
import 'package:praxino/core/subtitles/ai/deepseek_translator.dart';
import 'package:praxino/core/subtitles/ai/transcriber.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('SettingsStore persists watch history', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();
    final history = WatchHistory()
      ..record(WatchPoint(
        path: 'movie.mkv',
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 10),
        updatedAt: DateTime(2026, 1, 1),
      ));

    await store.saveWatchHistory(history);

    expect(store.watchHistory.find('movie.mkv')!.position,
        const Duration(seconds: 42));
  });

  test('SettingsStore persists AI subtitle settings', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();
    expect(store.aiSubtitles.whisperExecutable, isEmpty);
    expect(store.aiSubtitles.whisperFlavor, WhisperFlavor.whisperCpp);
    expect(store.aiSubtitles.model, DeepSeekModels.chat);
    expect(store.aiSubtitles.endpoint, kDeepSeekEndpoint);

    await store.setAiSubtitles(const AiSubtitleSettings(
      whisperExecutable: r'C:\Tools\whisper-cli.exe',
      whisperModel: r'C:\Tools\ggml-large-v3-turbo.bin',
      whisperFlavor: WhisperFlavor.whisperCpp,
      apiKey: 'local-only-key',
      model: DeepSeekModels.reasoner,
      endpoint: 'http://127.0.0.1:8080/v1/chat/completions',
      sourceLanguage: 'en',
    ));

    final saved = store.aiSubtitles;
    expect(saved.whisperExecutable, r'C:\Tools\whisper-cli.exe');
    expect(saved.whisperModel, r'C:\Tools\ggml-large-v3-turbo.bin');
    expect(saved.model, DeepSeekModels.reasoner);
    expect(saved.endpoint, 'http://127.0.0.1:8080/v1/chat/completions');
    expect(saved.sourceLanguage, 'en');
    expect(saved.hasApiKey, isTrue);
  });
}

