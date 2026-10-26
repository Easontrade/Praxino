import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/offline/offline_tools.dart';
import 'package:praxino/core/process/process_runner.dart';

class _FakeRunner implements ProcessRunner {
  _FakeRunner(this.paths);

  final Map<String, String?> paths;

  @override
  Future<ProcessOutput> run(String executable, List<String> arguments) async {
    final path = paths[arguments.first];
    return ProcessOutput(
      exitCode: path == null ? 1 : 0,
      stdout: path ?? '',
      stderr: '',
    );
  }
}

void main() {
  test('detects the tools through where', () async {
    final tools = await OfflineTools.detect(
      runner: _FakeRunner({
        'ffmpeg': r'C:\bin\ffmpeg.exe',
        'realesrgan-ncnn-vulkan': r'C:\bin\realesrgan.exe',
        'rife-ncnn-vulkan': null,
      }),
    );
    expect(tools.ffmpeg, r'C:\bin\ffmpeg.exe');
    expect(tools.realEsrgan, r'C:\bin\realesrgan.exe');
    expect(tools.rife, isNull);
    expect(tools.canEnhance, isTrue);
  });

  test('prefers configured paths when the files exist', () async {
    final temp = Directory.systemTemp.createTempSync('praxino-tools-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final ffmpeg = File('${temp.path}${Platform.pathSeparator}ffmpeg.exe')
      ..writeAsBytesSync([1]);

    final tools = await OfflineTools.detect(
      runner: _FakeRunner(const {}),
      ffmpegPath: ffmpeg.path,
    );
    expect(tools.ffmpeg, ffmpeg.path);
    expect(tools.canEnhance, isFalse);
  });

  test('builds extract, upscale, interpolate and encode stages', () {
    const tools = OfflineTools(
      ffmpeg: 'ffmpeg',
      realEsrgan: 'realesrgan',
      rife: 'rife',
    );
    final stages = OfflinePlan.build(
      tools: tools,
      input: r'C:\v\a.mkv',
      output: r'C:\v\a_enhanced.mp4',
      workDir: r'C:\v\a_work',
    );

    expect(stages, hasLength(4));
    expect(stages.first.arguments, contains('-r'));
    expect(stages[1].executable, 'realesrgan');
    expect(stages[1].arguments, contains('realesr-animevideov3'));
    expect(stages[2].executable, 'rife');
    expect(stages.last.arguments, contains('libx264'));
    expect(stages.last.arguments, contains('60'));
  });
}
