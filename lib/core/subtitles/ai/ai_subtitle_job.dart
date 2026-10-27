import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../enhance/offline/offline_job.dart';
import '../../process/process_runner.dart';
import 'bilingual_ass.dart';
import 'deepseek_translator.dart';
import 'transcriber.dart';
import 'transcript.dart';
import 'translator.dart';

/// Cache directory used when the settings leave it empty.
String defaultAiSubtitleCacheDir() {
  final local = Platform.environment['LOCALAPPDATA'];
  final root = local != null && local.trim().isNotEmpty
      ? local.trim()
      : Directory.systemTemp.path;
  return p.join(root, 'Praxino', 'ai-subtitles');
}

/// Everything the AI subtitle pipeline needs. Stored on this machine only; the
/// API key is never logged and never written into the project.
class AiSubtitleSettings {
  const AiSubtitleSettings({
    this.ffmpegExecutable = 'ffmpeg',
    this.whisperExecutable = '',
    this.whisperModel = '',
    this.whisperFlavor = WhisperFlavor.whisperCpp,
    this.apiKey = '',
    this.model = DeepSeekModels.chat,
    this.endpoint = kDeepSeekEndpoint,
    this.sourceLanguage,
    this.cacheDir,
    this.batchSize = 40,
    this.contextSize = 5,
  });

  final String ffmpegExecutable;
  final String whisperExecutable;
  final String whisperModel;
  final WhisperFlavor whisperFlavor;
  final String apiKey;
  final String model;

  /// OpenAI-compatible DeepSeek endpoint; configurable for proxies.
  final String endpoint;

  /// Optional ISO code such as `en`; empty means auto detect.
  final String? sourceLanguage;
  final String? cacheDir;

  /// Segments per translation request (the roadmap suggests 40-60 lines).
  final int batchSize;

  /// Neighbouring lines attached to a batch as read-only context.
  final int contextSize;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  bool get canTranscribe =>
      whisperExecutable.trim().isNotEmpty && whisperModel.trim().isNotEmpty;

  String get resolvedCacheDir {
    final value = cacheDir?.trim();
    return value == null || value.isEmpty
        ? defaultAiSubtitleCacheDir()
        : value;
  }

  String assPathFor(String sourcePath) => p.join(
        p.dirname(sourcePath),
        '${p.basenameWithoutExtension(sourcePath)}.zh-en.ass',
      );

  String srtPathFor(String sourcePath) => p.join(
        p.dirname(sourcePath),
        '${p.basenameWithoutExtension(sourcePath)}.zh.srt',
      );

  AiSubtitleSettings copyWith({
    String? ffmpegExecutable,
    String? whisperExecutable,
    String? whisperModel,
    WhisperFlavor? whisperFlavor,
    String? apiKey,
    String? model,
    String? endpoint,
    String? sourceLanguage,
    String? cacheDir,
    int? batchSize,
    int? contextSize,
  }) =>
      AiSubtitleSettings(
        ffmpegExecutable: ffmpegExecutable ?? this.ffmpegExecutable,
        whisperExecutable: whisperExecutable ?? this.whisperExecutable,
        whisperModel: whisperModel ?? this.whisperModel,
        whisperFlavor: whisperFlavor ?? this.whisperFlavor,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        endpoint: endpoint ?? this.endpoint,
        sourceLanguage: sourceLanguage ?? this.sourceLanguage,
        cacheDir: cacheDir ?? this.cacheDir,
        batchSize: batchSize ?? this.batchSize,
        contextSize: contextSize ?? this.contextSize,
      );

  Map<String, Object?> toJson() => {
        'ffmpeg': ffmpegExecutable,
        'whisperExe': whisperExecutable,
        'whisperModel': whisperModel,
        'whisperFlavor': whisperFlavor.name,
        'apiKey': apiKey,
        'model': model,
        'endpoint': endpoint,
        'sourceLanguage': sourceLanguage ?? '',
        'cacheDir': cacheDir ?? '',
        'batchSize': batchSize,
        'contextSize': contextSize,
      };

  static AiSubtitleSettings? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    String string(String key, [String fallback = '']) {
      final value = raw[key];
      return value is String ? value : fallback;
    }

    int integer(String key, int fallback) {
      final value = raw[key];
      return value is num && value > 0 ? value.toInt() : fallback;
    }

    final flavor = WhisperFlavor.values
        .where((value) => value.name == raw['whisperFlavor'])
        .firstOrNull;
    final language = string('sourceLanguage').trim();
    final cacheDir = string('cacheDir').trim();
    final endpoint = string('endpoint', kDeepSeekEndpoint).trim();
    // Settings saved before the DeepSeek switch stored Claude field names;
    // read them once so an update does not drop the user's key.
    final apiKey = string('apiKey', string('claudeApiKey'));
    var model = string('model', string('claudeModel', DeepSeekModels.chat));
    if (model.toLowerCase().contains('claude')) {
      model = DeepSeekModels.chat;
    }
    return AiSubtitleSettings(
      ffmpegExecutable: string('ffmpeg', 'ffmpeg'),
      whisperExecutable: string('whisperExe'),
      whisperModel: string('whisperModel'),
      whisperFlavor: flavor ?? WhisperFlavor.whisperCpp,
      apiKey: apiKey,
      model: model,
      endpoint: endpoint.isEmpty ? kDeepSeekEndpoint : endpoint,
      sourceLanguage: language.isEmpty ? null : language,
      cacheDir: cacheDir.isEmpty ? null : cacheDir,
      batchSize: integer('batchSize', 40),
      contextSize: integer('contextSize', 5),
    );
  }
}

/// One cached run: the transcript plus the aligned translations.
class AiSubtitleCacheEntry {
  const AiSubtitleCacheEntry({
    required this.key,
    required this.sourcePath,
    required this.segments,
    required this.translations,
    required this.createdAt,
    this.glossary = const {},
  });

  final String key;
  final String sourcePath;
  final List<TranscriptSegment> segments;
  final Map<int, String> translations;
  final Map<String, String> glossary;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'version': 1,
        'key': key,
        'source': sourcePath,
        'createdAt': createdAt.toIso8601String(),
        'segments': [for (final segment in segments) segment.toJson()],
        'translations': {
          for (final entry in translations.entries) '${entry.key}': entry.value,
        },
        'glossary': glossary,
      };

  static AiSubtitleCacheEntry? tryFromJson(Object? raw, {String? expectedKey}) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final source = raw['source'];
    if (key is! String || source is! String) return null;
    if (expectedKey != null && key != expectedKey) return null;
    final segments = TranscriptSegment.listFromJson(raw['segments']);
    if (segments.isEmpty) return null;
    final translations = _translationsFromJson(raw['translations']);
    if (translations.isEmpty) return null;
    final glossary = <String, String>{};
    final rawGlossary = raw['glossary'];
    if (rawGlossary is Map) {
      rawGlossary.forEach((source, target) {
        if (source is String && target is String) glossary[source] = target;
      });
    }
    return AiSubtitleCacheEntry(
      key: key,
      sourcePath: source,
      segments: segments,
      translations: translations,
      glossary: glossary,
      createdAt: DateTime.tryParse('${raw['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static Map<int, String> _translationsFromJson(Object? raw) {
    final result = <int, String>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final id = int.tryParse('$key');
        if (id == null || value is! String || value.trim().isEmpty) return;
        result[id] = value;
      });
    } else if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final id = item['id'];
        final chinese = item['zh'];
        if (id is! num || chinese is! String || chinese.trim().isEmpty) {
          continue;
        }
        result[id.toInt()] = chinese;
      }
    }
    return result;
  }
}

/// Transcript/translation cache keyed by the video fingerprint
/// (`absolute path | size | mtime`), so a repeated run never pays twice.
class AiSubtitleCache {
  const AiSubtitleCache(this.directory);

  final String directory;

  static String keyFor({
    required String sourcePath,
    required int size,
    required int modifiedMs,
  }) =>
      sha256.convert(utf8.encode('$sourcePath|$size|$modifiedMs')).toString();

  Future<String> keyForFile(String sourcePath) async {
    final file = File(sourcePath);
    final stat = await file.stat();
    return keyFor(
      sourcePath: file.absolute.path,
      size: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
    );
  }

  String pathFor(String key) => p.join(directory, '$key.json');

  /// Returns null for a missing, corrupt or stale cache file.
  Future<AiSubtitleCacheEntry?> load(String key) async {
    final file = File(pathFor(key));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return AiSubtitleCacheEntry.tryFromJson(decoded, expectedKey: key);
    } on Exception {
      return null;
    }
  }

  Future<void> save(AiSubtitleCacheEntry entry) async {
    await Directory(directory).create(recursive: true);
    final target = File(pathFor(entry.key));
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(entry.toJson()), flush: true);
    await temp.rename(target.path);
  }
}

typedef AiSubtitleCostConfirmation = Future<bool> Function(
    AiSubtitleCostEstimate estimate);

/// Runs one AI subtitle job: cache -> ffmpeg -> Whisper -> estimate ->
/// translate -> write `.zh-en.ass` + `.zh.srt`.
class AiSubtitleProcessor implements OfflineProcessor {
  AiSubtitleProcessor({
    required this.settings,
    Transcriber? transcriber,
    Translator? translator,
    ProcessRunner? processRunner,
    AiSubtitleCache? cache,
    http.Client? httpClient,
    this.confirmEstimate,
  })  : _runner = processRunner ?? const SystemProcessRunner(),
        _cache = cache ?? AiSubtitleCache(settings.resolvedCacheDir) {
    _transcriber = transcriber;
    _translator = translator;
    _httpClient = httpClient;
  }

  final AiSubtitleSettings settings;

  /// Called after transcription with the cost estimate; returning false
  /// aborts the job before any paid request is made.
  final AiSubtitleCostConfirmation? confirmEstimate;

  final ProcessRunner _runner;
  final AiSubtitleCache _cache;
  Transcriber? _transcriber;
  Translator? _translator;
  http.Client? _httpClient;
  DeepSeekTranslator? _ownedTranslator;

  @override
  Future<void> run(
    OfflineJob job, {
    required void Function(double progress) onProgress,
    required bool Function() stop,
  }) async {
    onProgress(0);
    if (stop()) return;

    final String key;
    try {
      key = await _cache.keyForFile(job.sourcePath);
    } on FileSystemException {
      throw OfflineException('读取视频文件失败：${job.sourcePath}');
    }
    if (stop()) return;

    final cached = await _cache.load(key);
    if (cached != null) {
      await _writeOutputs(job, cached.segments, cached.translations);
      onProgress(1);
      return;
    }

    if (_translator == null && !settings.hasApiKey) {
      throw const TranslationException(
          '未配置 DeepSeek API Key，请在“设置 → AI 双语字幕”里填写');
    }
    final translator = _ensureTranslator();

    Directory? workDir;
    try {
      workDir = await Directory.systemTemp.createTemp('praxino-ai-subtitles-');
      final wavPath = p.join(workDir.path, 'audio.wav');
      onProgress(0.05);
      await _extractAudio(job.sourcePath, wavPath);
      if (stop()) return;

      onProgress(0.2);
      final transcriber = _transcriber ??
          WhisperCliTranscriber(
            executable: settings.whisperExecutable,
            model: settings.whisperModel,
            flavor: settings.whisperFlavor,
            runner: _runner,
          );
      final segments = await transcriber.transcribe(
        wavPath,
        language: settings.sourceLanguage,
      );
      if (stop()) return;
      if (segments.isEmpty) {
        throw const OfflineException('没有识别到语音内容，无法生成字幕');
      }

      onProgress(0.35);
      final estimate = estimateTranslationCost(
        segments,
        translator.model,
        batchSize: settings.batchSize,
      );
      final confirm = confirmEstimate;
      if (confirm != null) {
        final accepted = await confirm(estimate);
        if (stop()) return;
        if (!accepted) {
          throw const OfflineException('已取消：没有确认翻译费用');
        }
      }

      final glossary = await translator.extractGlossary(segments);
      if (stop()) return;

      final translations = <int, String>{};
      final batches = buildTranslationBatches(
        segments,
        batchSize: settings.batchSize,
        contextSize: settings.contextSize,
      );
      for (var index = 0; index < batches.length; index++) {
        if (stop()) return;
        final result = await translator.translate(TranslationRequest(
          batch: batches[index],
          glossary: glossary,
          sourceLanguage: settings.sourceLanguage,
        ));
        translations.addAll(result.translations);
        onProgress(0.4 + 0.55 * (index + 1) / batches.length);
      }
      for (final segment in segments) {
        translations.putIfAbsent(segment.id, () => segment.text);
      }

      await _writeOutputs(job, segments, translations);
      await _cache.save(AiSubtitleCacheEntry(
        key: key,
        sourcePath: job.sourcePath,
        segments: segments,
        translations: translations,
        glossary: glossary,
        createdAt: DateTime.now(),
      ));
      onProgress(1);
    } finally {
      _ownedTranslator?.close();
      _ownedTranslator = null;
      final directory = workDir;
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // Best effort: a locked temp file must not fail the job.
        }
      }
    }
  }

  Translator _ensureTranslator() {
    final injected = _translator;
    if (injected != null) return injected;
    final endpoint = Uri.tryParse(settings.endpoint);
    final owned = DeepSeekTranslator(
      apiKey: settings.apiKey,
      model: settings.model,
      endpoint: endpoint != null && endpoint.hasScheme ? endpoint : null,
      client: _httpClient,
    );
    _ownedTranslator = owned;
    return owned;
  }

  Future<void> _extractAudio(String sourcePath, String wavPath) async {
    final ProcessOutput output;
    try {
      output = await _runner.run(settings.ffmpegExecutable, [
        '-hide_banner',
        '-nostdin',
        '-y',
        '-i',
        sourcePath,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'pcm_s16le',
        '-f',
        'wav',
        wavPath,
      ]);
    } on ProcessException catch (error) {
      throw OfflineException('无法启动 ffmpeg：${error.message}');
    }
    if (output.exitCode != 0) {
      throw OfflineException('提取音频失败：ffmpeg 退出码 ${output.exitCode}');
    }
  }

  Future<void> _writeOutputs(
    OfflineJob job,
    List<TranscriptSegment> segments,
    Map<int, String> translations,
  ) async {
    final assPath = job.outputPath.toLowerCase().endsWith('.ass')
        ? job.outputPath
        : settings.assPathFor(job.sourcePath);
    final srtPath = settings.srtPathFor(job.sourcePath);
    await File(assPath).parent.create(recursive: true);
    await File(srtPath).parent.create(recursive: true);
    await File(assPath).writeAsString(
      buildBilingualAss(
        segments: segments,
        translations: translations,
        title: p.basenameWithoutExtension(job.sourcePath),
      ),
      flush: true,
    );
    await File(srtPath).writeAsString(
      buildChineseSrt(segments: segments, translations: translations),
      flush: true,
    );
  }
}
