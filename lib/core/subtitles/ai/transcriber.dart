import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../process/process_runner.dart';
import 'transcript.dart';

/// Which local Whisper command line is installed.
///
/// `whisper.cpp` takes `-m model -f wav -oj -of base`; `faster-whisper` takes
/// the audio path first and writes its JSON into `--output_dir`.
enum WhisperFlavor { whisperCpp, fasterWhisper }

class TranscriptionException implements Exception {
  const TranscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class Transcriber {
  Future<List<TranscriptSegment>> transcribe(String wavPath, {String? language});
}

/// Reads a text file the tool wrote; injected so tests need no filesystem.
typedef WhisperTextReader = Future<String?> Function(String path);

/// Runs a local Whisper command line on a 16 kHz mono WAV and parses its JSON.
class WhisperCliTranscriber implements Transcriber {
  WhisperCliTranscriber({
    required this.executable,
    required this.model,
    this.flavor = WhisperFlavor.whisperCpp,
    this.runner = const SystemProcessRunner(),
    this.readTextFile = readTextIfExists,
    this.timeout = const Duration(minutes: 30),
  });

  final String executable;
  final String model;
  final WhisperFlavor flavor;
  final ProcessRunner runner;
  final WhisperTextReader readTextFile;
  final Duration timeout;

  static Future<String?> readTextIfExists(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<List<TranscriptSegment>> transcribe(
    String wavPath, {
    String? language,
  }) async {
    final exe = executable.trim();
    if (exe.isEmpty) {
      throw const TranscriptionException(
          '未配置 Whisper 可执行文件，请在“设置 → AI 双语字幕”里填写');
    }
    if (model.trim().isEmpty) {
      throw const TranscriptionException(
          '未配置 Whisper 模型，请在“设置 → AI 双语字幕”里填写');
    }
    final lang = (language ?? '').trim();

    final workDir = await Directory.systemTemp.createTemp('praxino-whisper-');
    try {
      final outputBase = p.join(workDir.path, 'transcript');
      final arguments = switch (flavor) {
        WhisperFlavor.whisperCpp => [
            '-m',
            model.trim(),
            '-f',
            wavPath,
            '-oj',
            '-of',
            outputBase,
            '-l',
            lang.isEmpty ? 'auto' : lang,
          ],
        WhisperFlavor.fasterWhisper => [
            wavPath,
            '--model',
            model.trim(),
            '--output_format',
            'json',
            '--output_dir',
            workDir.path,
            if (lang.isNotEmpty) ...['--language', lang],
          ],
      };

      final ProcessOutput output;
      try {
        output = await runner.run(exe, arguments).timeout(timeout);
      } on TimeoutException {
        throw TranscriptionException('语音识别超时（${timeout.inMinutes} 分钟）');
      } on ProcessException catch (error) {
        throw TranscriptionException('无法启动 Whisper：${error.message}');
      }
      if (output.exitCode != 0) {
        throw TranscriptionException(
            '语音识别失败：Whisper 退出码 ${output.exitCode}');
      }

      final json = _inlineJson(output.stdout) ?? await _readJsonFile(
        outputBase: outputBase,
        wavPath: wavPath,
      );
      if (json == null || json.trim().isEmpty) {
        throw const TranscriptionException(
            'Whisper 没有生成 JSON 结果，请检查模型路径和 Whisper 版本');
      }
      final segments = parseWhisperJson(json, flavor: flavor);
      if (segments.isEmpty) {
        throw const TranscriptionException('Whisper 没有识别到语音内容');
      }
      return segments;
    } finally {
      // The temp directory only holds the tool output, never the source video.
      try {
        await workDir.delete(recursive: true);
      } on FileSystemException {
        // Best effort: a locked temp directory must not fail the job.
      }
    }
  }

  Future<String?> _readJsonFile({
    required String outputBase,
    required String wavPath,
  }) async {
    final candidates = switch (flavor) {
      WhisperFlavor.whisperCpp => ['$outputBase.json'],
      WhisperFlavor.fasterWhisper => [
          p.join(p.dirname(outputBase),
              '${p.basenameWithoutExtension(wavPath)}.json'),
        ],
    };
    for (final candidate in candidates) {
      final text = await readTextFile(candidate);
      if (text != null && text.trim().isNotEmpty) return text;
    }
    return null;
  }
}

/// Some builds print the JSON document on stdout instead of (or in addition
/// to) writing a file. Anything else on stdout is ignored.
String? _inlineJson(String stdout) {
  final trimmed = stdout.trim();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) return trimmed;
  return null;
}

/// Parses whisper.cpp or faster-whisper JSON.
///
/// Accepts either a bare array or an object with `segments`/`transcription`.
/// whisper.cpp writes `offsets` in milliseconds and `timestamps` as clock
/// strings, faster-whisper writes `start`/`end` in seconds; [flavor] decides
/// how bare numbers are interpreted.
List<TranscriptSegment> parseWhisperJson(
  String raw, {
  WhisperFlavor flavor = WhisperFlavor.whisperCpp,
}) {
  final decoded = _decode(raw);
  final entries = _entries(decoded);
  final segments = <TranscriptSegment>[];
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    if (entry is! Map) continue;
    final text = entry['text'];
    if (text is! String || text.trim().isEmpty) continue;
    final timing = _timing(entry, flavor);
    if (timing == null) continue;
    final id = entry['id'];
    segments.add(TranscriptSegment(
      id: id is num ? id.toInt() : index + 1,
      start: timing.$1,
      end: timing.$2,
      text: text.trim(),
    ));
  }
  return segments;
}

Object? _decode(String raw) {
  final cleaned = _stripFence(raw);
  try {
    return jsonDecode(cleaned);
  } on FormatException {
    throw const TranscriptionException('Whisper 输出的 JSON 无法解析');
  }
}

String _stripFence(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.contains('```')) return trimmed;
  final start = trimmed.indexOf('```');
  var body = trimmed.substring(start + 3);
  if (body.toLowerCase().startsWith('json')) body = body.substring(4);
  final end = body.indexOf('```');
  if (end >= 0) body = body.substring(0, end);
  return body.trim();
}

List<Object?> _entries(Object? decoded) {
  if (decoded is List) return decoded;
  if (decoded is Map) {
    final segments = decoded['segments'];
    if (segments is List && segments.isNotEmpty) return segments;
    final transcription = decoded['transcription'];
    if (transcription is List && transcription.isNotEmpty) {
      return transcription;
    }
    if (segments is List) return segments;
  }
  return const [];
}

(Duration, Duration)? _timing(Map<Object?, Object?> entry, WhisperFlavor flavor) {
  final offsets = entry['offsets'];
  if (offsets is Map) {
    final from = offsets['from'];
    final to = offsets['to'];
    if (from is num && to is num) {
      return (_milliseconds(from), _milliseconds(to));
    }
  }
  final stamps = entry['timestamps'];
  if (stamps is Map) {
    final from = _clock(stamps['from']);
    final to = _clock(stamps['to']);
    if (from != null && to != null) return (from, to);
  }
  final start = entry['start'];
  final end = entry['end'];
  if (start is num && end is num) {
    return flavor == WhisperFlavor.fasterWhisper
        ? (_seconds(start), _seconds(end))
        : (_milliseconds(start), _milliseconds(end));
  }
  return null;
}

Duration _milliseconds(num value) =>
    Duration(milliseconds: value.round());

Duration _seconds(num value) =>
    Duration(microseconds: (value * Duration.microsecondsPerSecond).round());

/// Parses `HH:MM:SS,mmm` / `HH:MM:SS.mmm` (whisper.cpp `timestamps`) or a
/// plain number of seconds.
Duration? _clock(Object? value) {
  if (value is num) return _seconds(value);
  if (value is! String) return null;
  final match =
      RegExp(r'(\d+):(\d+):(\d+)(?:[.,](\d+))?').firstMatch(value.trim());
  if (match == null) return null;
  final hours = int.tryParse(match.group(1)!);
  final minutes = int.tryParse(match.group(2)!);
  final seconds = int.tryParse(match.group(3)!);
  final fraction = match.group(4);
  if (hours == null || minutes == null || seconds == null) return null;
  var millis = 0;
  if (fraction != null && fraction.isNotEmpty) {
    final padded = fraction.padRight(3, '0').substring(0, 3);
    millis = int.tryParse(padded) ?? 0;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}
