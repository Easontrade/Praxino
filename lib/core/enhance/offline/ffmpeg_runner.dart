import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'offline_job.dart';

/// Parses ffmpeg's `time=HH:MM:SS.mm` progress lines.
class FfmpegProgress {
  FfmpegProgress._();

  static final RegExp _time = RegExp(r'time=(\d+):(\d+):(\d+(?:\.\d+)?)');

  static Duration? parseTime(String line) {
    final match = _time.firstMatch(line);
    if (match == null) return null;
    final hours = int.tryParse(match.group(1)!);
    final minutes = int.tryParse(match.group(2)!);
    final seconds = double.tryParse(match.group(3)!);
    if (hours == null || minutes == null || seconds == null) return null;
    return Duration(
      hours: hours,
      minutes: minutes,
      milliseconds: (seconds * 1000).round(),
    );
  }

  static double? fraction(String line, Duration total) {
    final time = parseTime(line);
    if (time == null || total.inMilliseconds <= 0) return null;
    return (time.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Runs ffmpeg and reports stderr lines; the process is killed when [stop]
/// becomes true.
class FfmpegRunner {
  FfmpegRunner({this.ffmpeg = 'ffmpeg'});

  final String ffmpeg;

  Future<void> run({
    required List<String> arguments,
    required void Function(String line) onLine,
    required bool Function() stop,
  }) async {
    final process = await Process.start(ffmpeg, arguments);
    final lines = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine);
    final killer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (stop()) process.kill();
    });
    try {
      final code = await process.exitCode;
      if (code != 0) throw OfflineException('ffmpeg 退出码 $code');
    } finally {
      killer.cancel();
      await lines.cancel();
    }
  }
}

/// Baseline ffmpeg encode; the GPU upscale/interpolation stage is prepended
/// by a configured tool when one is available.
class FfmpegOfflineProcessor implements OfflineProcessor {
  FfmpegOfflineProcessor({
    required this.runner,
    this.totalDuration,
  });

  final FfmpegRunner runner;
  final Duration? totalDuration;

  @override
  Future<void> run(
    OfflineJob job, {
    required void Function(double progress) onProgress,
    required bool Function() stop,
  }) async {
    await runner.run(
      arguments: [
        '-y',
        '-i',
        job.sourcePath,
        '-c:v',
        'libx264',
        '-crf',
        '18',
        '-c:a',
        'copy',
        job.outputPath,
      ],
      onLine: (line) {
        final total = totalDuration;
        if (total == null) return;
        final fraction = FfmpegProgress.fraction(line, total);
        if (fraction != null) onProgress(fraction);
      },
      stop: stop,
    );
  }
}
