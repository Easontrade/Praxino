import 'dart:io';

import 'package:path/path.dart' as p;

import '../../process/process_runner.dart';
import 'offline_job.dart';
import 'offline_tools.dart';

/// Runs the real ffmpeg -> Real-ESRGAN -> optional RIFE -> ffmpeg pipeline.
class GpuOfflineProcessor implements OfflineProcessor {
  GpuOfflineProcessor({
    required this.tools,
    this.scale = 2,
    this.fps = 30,
    ProcessRunner? runner,
  }) : _runner = runner ?? const SystemProcessRunner();

  final OfflineTools tools;
  final int scale;
  final int fps;
  final ProcessRunner _runner;

  @override
  Future<void> run(
    OfflineJob job, {
    required void Function(double progress) onProgress,
    required bool Function() stop,
  }) async {
    if (!tools.canEnhance) {
      throw const OfflineException('缺少 ffmpeg 或 GPU 增强工具');
    }
    final work = Directory(p.join(
      p.dirname(job.outputPath),
      '.praxino_offline_${job.id}',
    ));
    if (await work.exists()) {
      await work.delete(recursive: true);
    }
    await work.create(recursive: true);
    for (final name in ['frames', 'upscaled', 'interpolated']) {
      await Directory(p.join(work.path, name)).create(recursive: true);
    }
    final stages = OfflinePlan.build(
      tools: tools,
      input: job.sourcePath,
      output: job.outputPath,
      workDir: work.path,
      scale: scale,
      fps: fps,
    );
    try {
      for (var i = 0; i < stages.length; i++) {
        if (stop()) return;
        final stage = stages[i];
        final output = await _runner.run(stage.executable, stage.arguments);
        if (output.exitCode != 0) {
          throw OfflineException(
            '${p.basename(stage.executable)} 失败（${output.exitCode}）：'
            '${_tail(output.stderr)}',
          );
        }
        onProgress((i + 1) / stages.length);
      }
    } finally {
      try {
        await work.delete(recursive: true);
      } on FileSystemException {
        // Keep the output even if temp cleanup fails.
      }
    }
  }

  static String _tail(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= 300) return trimmed;
    return trimmed.substring(trimmed.length - 300);
  }
}
