import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:praxino/core/enhance/offline/offline_job.dart';
import 'package:praxino/core/process/process_runner.dart';
import 'package:praxino/core/subtitles/ai/ai_subtitle_job.dart';
import 'package:praxino/core/subtitles/ai/deepseek_translator.dart';
import 'package:praxino/core/subtitles/ai/transcriber.dart';
import 'package:praxino/core/subtitles/ai/transcript.dart';
import 'package:praxino/core/subtitles/ai/translator.dart';

const _segments = [
  TranscriptSegment(
    id: 1,
    start: Duration.zero,
    end: Duration(seconds: 2),
    text: 'Hello one',
  ),
  TranscriptSegment(
    id: 2,
    start: Duration(seconds: 2),
    end: Duration(seconds: 4),
    text: 'Hello two',
  ),
  TranscriptSegment(
    id: 3,
    start: Duration(seconds: 4),
    end: Duration(seconds: 6),
    text: 'Hello three',
  ),
];

class _FakeRunner implements ProcessRunner {
  _FakeRunner(this.onRun);

  final Future<ProcessOutput> Function(List<String> arguments) onRun;
  final List<String> executables = [];
  final List<List<String>> calls = [];

  @override
  Future<ProcessOutput> run(String executable, List<String> arguments) async {
    executables.add(executable);
    calls.add(arguments);
    return onRun(arguments);
  }
}

ProcessOutput _ok() =>
    const ProcessOutput(exitCode: 0, stdout: '', stderr: '');

/// Writes a fake WAV so the tests can prove the temp audio is deleted again.
Future<ProcessOutput> _writeFakeWav(List<String> arguments) async {
  await File(arguments.last).writeAsString('RIFF');
  return _ok();
}

class _FakeTranscriber implements Transcriber {
  _FakeTranscriber(this.segments);

  final List<TranscriptSegment> segments;
  int calls = 0;
  final List<String> wavPaths = [];

  @override
  Future<List<TranscriptSegment>> transcribe(
    String wavPath, {
    String? language,
  }) async {
    calls++;
    wavPaths.add(wavPath);
    return segments;
  }
}

class _ExplodingTranscriber implements Transcriber {
  @override
  Future<List<TranscriptSegment>> transcribe(
    String wavPath, {
    String? language,
  }) async {
    throw StateError('Whisper must not run on a cache hit');
  }
}

class _FakeTranslator implements Translator {
  @override
  final String model = DeepSeekModels.chat;
  int glossaryCalls = 0;
  int translateCalls = 0;
  final List<TranslationBatch> batches = [];
  final List<String?> languages = [];

  @override
  Future<Map<String, String>> extractGlossary(
    List<TranscriptSegment> segments,
  ) async {
    glossaryCalls++;
    return const {'Praxino': '普拉克西诺'};
  }

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    translateCalls++;
    batches.add(request.batch);
    languages.add(request.sourceLanguage);
    return TranslationResult(
      translations: {
        for (final segment in request.batch.segments)
          segment.id: '译${segment.id}',
      },
    );
  }
}

class _ExplodingTranslator implements Translator {
  @override
  String get model => DeepSeekModels.chat;

  @override
  Future<Map<String, String>> extractGlossary(
    List<TranscriptSegment> segments,
  ) async {
    throw StateError('the API must not be called on a cache hit');
  }

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    throw StateError('the API must not be called on a cache hit');
  }
}

class _Recorder implements OfflineProcessor {
  final List<OfflineJobKind> kinds = [];

  @override
  Future<void> run(
    OfflineJob job, {
    required void Function(double progress) onProgress,
    required bool Function() stop,
  }) async {
    kinds.add(job.kind);
    onProgress(1);
  }
}

Future<File> _video(Directory directory) async {
  final file = File(p.join(directory.path, 'sample.mkv'));
  await file.writeAsBytes(List<int>.filled(2048, 7));
  return file;
}

Future<Directory> _tempDir() async {
  final directory = await Directory.systemTemp.createTemp('praxino-ai-job-');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  return directory;
}

void main() {
  test('runs ffmpeg, Whisper, the estimate and translation, then writes files',
      () async {
    final dir = await _tempDir();
    final video = await _video(dir);
    final runner = _FakeRunner(_writeFakeWav);
    final transcriber = _FakeTranscriber(_segments);
    final translator = _FakeTranslator();
    AiSubtitleCostEstimate? estimate;
    final progress = <double>[];
    final processor = AiSubtitleProcessor(
      settings: AiSubtitleSettings(
        ffmpegExecutable: 'ffmpeg-test',
        whisperExecutable: 'whisper-test',
        whisperModel: 'model-test',
        apiKey: 'test-key',
        cacheDir: p.join(dir.path, 'cache'),
      ),
      transcriber: transcriber,
      translator: translator,
      processRunner: runner,
      confirmEstimate: (value) async {
        estimate = value;
        return true;
      },
    );
    final job = OfflineJob.forAiSubtitle(video.path, id: 'job-1');

    await processor.run(job, onProgress: progress.add, stop: () => false);

    expect(runner.executables.single, 'ffmpeg-test');
    expect(
      runner.calls.single,
      containsAllInOrder([
        '-i',
        video.path,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
      ]),
    );
    expect(transcriber.calls, 1);
    expect(translator.glossaryCalls, 1);
    expect(translator.translateCalls, 1);
    expect(estimate, isNotNull);
    expect(estimate!.segmentCount, 3);
    expect(estimate!.model, DeepSeekModels.chat);
    expect(estimate!.estimatedUsd, greaterThan(0));
    expect(progress.first, 0);
    expect(progress.last, 1);
    expect(progress.every((value) => value >= 0 && value <= 1), isTrue);

    final ass = await File(job.outputPath).readAsString();
    expect(ass, contains('Dialogue:'));
    expect(ass, contains('译1'));
    expect(ass, contains('Hello one'));
    expect(ass, contains('PlayResX: 1920'));

    final srtFile = File(p.join(dir.path, 'sample.zh.srt'));
    expect(await srtFile.exists(), isTrue);
    expect(await srtFile.readAsString(), contains('译1'));

    // The temporary 16 kHz WAV is removed after the run.
    expect(File(transcriber.wavPaths.single).existsSync(), isFalse);
  });

  test('a repeat run hits the cache and makes no API or Whisper call',
      () async {
    final dir = await _tempDir();
    final video = await _video(dir);
    final settings = AiSubtitleSettings(
      apiKey: 'test-key',
      cacheDir: p.join(dir.path, 'cache'),
    );
    final job = OfflineJob.forAiSubtitle(video.path, id: 'job');

    final first = AiSubtitleProcessor(
      settings: settings,
      transcriber: _FakeTranscriber(_segments),
      translator: _FakeTranslator(),
      processRunner: _FakeRunner(_writeFakeWav),
    );
    await first.run(job, onProgress: (_) {}, stop: () => false);
    final firstAss = await File(job.outputPath).readAsString();
    await File(job.outputPath).delete();
    await File(p.join(dir.path, 'sample.zh.srt')).delete();

    final secondRunner = _FakeRunner((arguments) async => _ok());
    final second = AiSubtitleProcessor(
      settings: settings,
      transcriber: _ExplodingTranscriber(),
      translator: _ExplodingTranslator(),
      processRunner: secondRunner,
    );
    await second.run(job, onProgress: (_) {}, stop: () => false);

    expect(secondRunner.calls, isEmpty);
    expect(await File(job.outputPath).readAsString(), firstAss);
    expect(await File(p.join(dir.path, 'sample.zh.srt')).exists(), isTrue);
  });

  test('changing the video invalidates the cache', () async {
    final dir = await _tempDir();
    final video = await _video(dir);
    final settings = AiSubtitleSettings(
      apiKey: 'test-key',
      cacheDir: p.join(dir.path, 'cache'),
    );
    final job = OfflineJob.forAiSubtitle(video.path, id: 'job');

    await AiSubtitleProcessor(
      settings: settings,
      transcriber: _FakeTranscriber(_segments),
      translator: _FakeTranslator(),
      processRunner: _FakeRunner(_writeFakeWav),
    ).run(job, onProgress: (_) {}, stop: () => false);

    await video.writeAsBytes(List<int>.filled(4096, 8));
    final transcriber = _FakeTranscriber(_segments);
    final translator = _FakeTranslator();
    await AiSubtitleProcessor(
      settings: settings,
      transcriber: transcriber,
      translator: translator,
      processRunner: _FakeRunner(_writeFakeWav),
    ).run(job, onProgress: (_) {}, stop: () => false);

    expect(transcriber.calls, 1);
    expect(translator.translateCalls, 1);
  });

  test('a corrupt cache file is ignored and repaired', () async {
    final dir = await _tempDir();
    final video = await _video(dir);
    final cacheDir = p.join(dir.path, 'cache');
    final cache = AiSubtitleCache(cacheDir);
    final key = await cache.keyForFile(video.path);
    await Directory(cacheDir).create(recursive: true);
    await File(cache.pathFor(key)).writeAsString('{not json');

    final transcriber = _FakeTranscriber(_segments);
    final translator = _FakeTranslator();
    final job = OfflineJob.forAiSubtitle(video.path, id: 'job');
    await AiSubtitleProcessor(
      settings: AiSubtitleSettings(
        apiKey: 'test-key',
        cacheDir: cacheDir,
      ),
      transcriber: transcriber,
      translator: translator,
      processRunner: _FakeRunner(_writeFakeWav),
    ).run(job, onProgress: (_) {}, stop: () => false);

    expect(transcriber.calls, 1);
    expect(translator.translateCalls, 1);
    final repaired = await cache.load(key);
    expect(repaired, isNotNull);
    expect(repaired!.segments, hasLength(3));
    expect(repaired.translations[2], '译2');
  });

  test('declining the estimate aborts without files, cache or API calls',
      () async {
    final dir = await _tempDir();
    final video = await _video(dir);
    final cacheDir = p.join(dir.path, 'cache');
    final translator = _FakeTranslator();
    String? wavPath;
    final runner = _FakeRunner((arguments) async {
      wavPath = arguments.last;
      return _writeFakeWav(arguments);
    });
    final processor = AiSubtitleProcessor(
      settings: AiSubtitleSettings(
        apiKey: 'test-key',
        cacheDir: cacheDir,
      ),
      transcriber: _FakeTranscriber(_segments),
      translator: translator,
      processRunner: runner,
      confirmEstimate: (_) async => false,
    );
    final job = OfflineJob.forAiSubtitle(video.path, id: 'job');

    await expectLater(
      processor.run(job, onProgress: (_) {}, stop: () => false),
      throwsA(isA<OfflineException>().having(
        (error) => error.message,
        'message',
        contains('费用'),
      )),
    );

    expect(translator.glossaryCalls, 0);
    expect(translator.translateCalls, 0);
    expect(File(job.outputPath).existsSync(), isFalse);
    expect(File(p.join(dir.path, 'sample.zh.srt')).existsSync(), isFalse);
    expect(Directory(cacheDir).existsSync(), isFalse);
    expect(wavPath, isNotNull);
    expect(File(wavPath!).existsSync(), isFalse);
  });

  test('a missing DeepSeek API key fails before rendering any media', () async {
    final dir = await _tempDir();
    final video = await _video(dir);
    final runner = _FakeRunner(_writeFakeWav);
    final processor = AiSubtitleProcessor(
      settings: AiSubtitleSettings(
        whisperExecutable: 'whisper',
        whisperModel: 'model',
        cacheDir: p.join(dir.path, 'cache'),
      ),
      transcriber: _FakeTranscriber(_segments),
      processRunner: runner,
    );
    final job = OfflineJob.forAiSubtitle(video.path, id: 'job');

    await expectLater(
      processor.run(job, onProgress: (_) {}, stop: () => false),
      throwsA(isA<TranslationException>().having(
        (error) => error.message,
        'message',
        contains('API Key'),
      )),
    );
    expect(runner.calls, isEmpty);
    expect(File(job.outputPath).existsSync(), isFalse);
  });

  test('translates in batches of about 40 with 5 context lines', () async {
    final dir = await _tempDir();
    final video = await _video(dir);
    final segments = [
      for (var index = 1; index <= 90; index++)
        TranscriptSegment(
          id: index,
          start: Duration(seconds: index),
          end: Duration(seconds: index + 1),
          text: 'line $index',
        ),
    ];
    final translator = _FakeTranslator();
    await AiSubtitleProcessor(
      settings: AiSubtitleSettings(
        apiKey: 'test-key',
        sourceLanguage: 'en',
        cacheDir: p.join(dir.path, 'cache'),
      ),
      transcriber: _FakeTranscriber(segments),
      translator: translator,
      processRunner: _FakeRunner(_writeFakeWav),
      confirmEstimate: (_) async => true,
    ).run(
      OfflineJob.forAiSubtitle(video.path, id: 'job'),
      onProgress: (_) {},
      stop: () => false,
    );

    expect(translator.batches, hasLength(3));
    expect(translator.batches[0].segments, hasLength(40));
    expect(translator.batches[1].segments, hasLength(40));
    expect(translator.batches[2].segments, hasLength(10));
    expect(translator.batches.first.contextBefore, isEmpty);
    expect(translator.batches.first.contextAfter, hasLength(5));
    expect(translator.batches[1].contextBefore, hasLength(5));
    expect(translator.batches[1].contextAfter, hasLength(5));
    expect(translator.batches.last.contextAfter, isEmpty);
    expect(translator.languages, everyElement('en'));
  });

  test('returns without side effects when the queue stops the job', () async {
    final dir = await _tempDir();
    final video = await _video(dir);
    final runner = _FakeRunner(_writeFakeWav);
    final transcriber = _FakeTranscriber(_segments);
    final processor = AiSubtitleProcessor(
      settings: AiSubtitleSettings(
        apiKey: 'test-key',
        cacheDir: p.join(dir.path, 'cache'),
      ),
      transcriber: transcriber,
      translator: _FakeTranslator(),
      processRunner: runner,
    );
    final job = OfflineJob.forAiSubtitle(video.path, id: 'job');

    await processor.run(job, onProgress: (_) {}, stop: () => true);

    expect(runner.calls, isEmpty);
    expect(transcriber.calls, 0);
    expect(File(job.outputPath).existsSync(), isFalse);
  });

  test('old persisted jobs without a type load as enhance jobs', () {
    final job = OfflineJob.tryFromJson({
      'id': 'legacy',
      'source': r'C:\videos\a.mkv',
      'output': r'C:\videos\a_enhanced.mp4',
      'status': 'queued',
      'progress': 0.5,
    });
    expect(job, isNotNull);
    expect(job!.kind, OfflineJobKind.enhance);
    expect(job.progress, 0.5);
  });

  test('AI subtitle jobs keep their kind and ASS output path', () {
    final job = OfflineJob.forAiSubtitle(r'C:\videos\a.mkv', id: 'ai');
    expect(job.kind, OfflineJobKind.aiSubtitle);
    expect(job.outputPath, endsWith('a.zh-en.ass'));
    expect(job.outputPath, isNot(endsWith('_enhanced.mp4')));

    final restored = OfflineJob.tryFromJson(job.toJson());
    expect(restored!.kind, OfflineJobKind.aiSubtitle);
    expect(restored.outputPath, job.outputPath);
    expect( restored.copyWith(status: OfflineJobStatus.running).kind,
        OfflineJobKind.aiSubtitle);
  });

  test('the routing processor dispatches by job kind', () async {
    final enhance = _Recorder();
    final ai = _Recorder();
    final router = RoutingOfflineProcessor(
      enhanceProcessor: enhance,
      aiSubtitleProcessor: ai,
    );

    await router.run(
      OfflineJob.forSource(r'C:\videos\a.mkv'),
      onProgress: (_) {},
      stop: () => false,
    );
    await router.run(
      OfflineJob.forAiSubtitle(r'C:\videos\a.mkv'),
      onProgress: (_) {},
      stop: () => false,
    );

    expect(enhance.kinds, [OfflineJobKind.enhance]);
    expect(ai.kinds, [OfflineJobKind.aiSubtitle]);
  });

  test('AI subtitle settings round-trip through JSON', () {
    const settings = AiSubtitleSettings(
      whisperExecutable: r'C:\Tools\whisper.exe',
      whisperModel: 'large-v3',
      whisperFlavor: WhisperFlavor.fasterWhisper,
      apiKey: 'local-key',
      model: DeepSeekModels.reasoner,
      endpoint: 'http://127.0.0.1:1234/v1/chat/completions',
      sourceLanguage: 'en',
      cacheDir: r'C:\Cache',
    );
    final restored =
        AiSubtitleSettings.tryFromJson(jsonDecode(jsonEncode(settings.toJson())));
    expect(restored, isNotNull);
    expect(restored!.whisperExecutable, r'C:\Tools\whisper.exe');
    expect(restored.whisperModel, 'large-v3');
    expect(restored.whisperFlavor, WhisperFlavor.fasterWhisper);
    expect(restored.apiKey, 'local-key');
    expect(restored.model, DeepSeekModels.reasoner);
    expect(restored.endpoint, 'http://127.0.0.1:1234/v1/chat/completions');
    expect(restored.sourceLanguage, 'en');
    expect(restored.cacheDir, r'C:\Cache');

    final defaults = AiSubtitleSettings.tryFromJson(const <String, Object?>{});
    expect(defaults!.whisperFlavor, WhisperFlavor.whisperCpp);
    expect(defaults.model, DeepSeekModels.chat);
    expect(defaults.endpoint, kDeepSeekEndpoint);
    expect(defaults.sourceLanguage, isNull);
    expect(defaults.cacheDir, isNull);
  });

  test('settings saved with Claude field names migrate to DeepSeek', () {
    final restored = AiSubtitleSettings.tryFromJson(const {
      'claudeApiKey': 'old-key',
      'claudeModel': 'claude-haiku-5-5',
    });
    expect(restored, isNotNull);
    expect(restored!.apiKey, 'old-key');
    expect(restored.model, DeepSeekModels.chat);
    expect(restored.endpoint, kDeepSeekEndpoint);
  });

  test('bilingual output paths sit next to the video', () {
    const settings = AiSubtitleSettings();
    expect(settings.assPathFor(r'C:\videos\a.mkv'), endsWith('a.zh-en.ass'));
    expect(settings.srtPathFor(r'C:\videos\a.mkv'), endsWith('a.zh.srt'));
  });
}

