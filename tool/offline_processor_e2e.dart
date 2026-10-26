import 'dart:io';

import 'package:praxino/core/enhance/offline/gpu_processor.dart';
import 'package:praxino/core/enhance/offline/offline_job.dart';
import 'package:praxino/core/enhance/offline/offline_tools.dart';
import 'package:praxino/core/process/process_runner.dart';

/// Paths come from environment variables so no machine layout is committed:
/// PRAXINO_FFMPEG, PRAXINO_ESRGAN, PRAXINO_RIFE, PRAXINO_RIFE_MODEL,
/// PRAXINO_E2E_SOURCE, PRAXINO_E2E_OUTPUT.
String _env(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    stderr.writeln('Missing environment variable $name');
    exit(64);
  }
  return value;
}

Future<void> main() async {
  final tools = OfflineTools(
    ffmpeg: _env('PRAXINO_FFMPEG'),
    realEsrgan: _env('PRAXINO_ESRGAN'),
    rife: _env('PRAXINO_RIFE'),
    rifeModel: _env('PRAXINO_RIFE_MODEL'),
  );
  final source = File(_env('PRAXINO_E2E_SOURCE'));
  final output = File(_env('PRAXINO_E2E_OUTPUT'));
  final job = OfflineJob(
    id: 'app-e2e',
    sourcePath: source.path,
    outputPath: output.path,
    createdAt: DateTime.now(),
  );
  final processor = GpuOfflineProcessor(
    tools: tools,
    fps: 24,
    runner: const SystemProcessRunner(),
  );
  try {
    await processor.run(
      job,
      onProgress: (progress) =>
          stdout.writeln('progress ${(progress * 100).toStringAsFixed(0)}%'),
      stop: () => false,
    );
    stdout.writeln('output exists=${await output.exists()} '
        'size=${await output.length()}');
  } on Exception catch (error) {
    stdout.writeln('failed: $error');
    exitCode = 1;
  }
}
