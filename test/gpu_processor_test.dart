import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/offline/gpu_processor.dart';
import 'package:praxino/core/enhance/offline/offline_job.dart';
import 'package:praxino/core/enhance/offline/offline_tools.dart';
import 'package:praxino/core/process/process_runner.dart';

class _RecordingRunner implements ProcessRunner {
  _RecordingRunner({this.failAt = -1});

  final int failAt;
  final List<List<String>> calls = [];

  @override
  Future<ProcessOutput> run(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    final index = calls.length - 1;
    return ProcessOutput(
      exitCode: index == failAt ? 1 : 0,
      stdout: '',
      stderr: index == failAt ? 'boom' : '',
    );
  }
}

OfflineJob _job() => OfflineJob(
      id: 'gpu',
      sourcePath: 'C:/v/a.mkv',
      outputPath: 'C:/v/a_enhanced.mp4',
      createdAt: DateTime(2026),
    );

void main() {
  test('runs all four GPU stages and reports progress', () async {
    final runner = _RecordingRunner();
    final processor = GpuOfflineProcessor(
      tools: const OfflineTools(
        ffmpeg: 'ffmpeg',
        realEsrgan: 'realesrgan',
        rife: 'rife',
      ),
      runner: runner,
    );
    final progress = <double>[];

    await processor.run(
      _job(),
      onProgress: progress.add,
      stop: () => false,
    );

    expect(runner.calls, hasLength(4));
    expect(progress, [0.25, 0.5, 0.75, 1.0]);
  });

  test('fails with stderr tail and stops the pipeline', () async {
    final runner = _RecordingRunner(failAt: 1);
    final processor = GpuOfflineProcessor(
      tools: const OfflineTools(ffmpeg: 'ffmpeg', realEsrgan: 'realesrgan'),
      runner: runner,
    );

    await expectLater(
      processor.run(_job(), onProgress: (_) {}, stop: () => false),
      throwsA(isA<OfflineException>()),
    );
    expect(runner.calls, hasLength(2));
  });

  test('stop before a stage leaves the rest unrun', () async {
    final runner = _RecordingRunner();
    final processor = GpuOfflineProcessor(
      tools: const OfflineTools(ffmpeg: 'ffmpeg', realEsrgan: 'realesrgan'),
      runner: runner,
    );
    var stopped = false;

    await processor.run(
      _job(),
      onProgress: (_) => stopped = true,
      stop: () => stopped,
    );

    expect(runner.calls.length, lessThan(3));
  });
}
