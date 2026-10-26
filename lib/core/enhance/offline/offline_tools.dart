import 'dart:io';

import 'package:path/path.dart' as p;

import '../../process/process_runner.dart';

/// External executables used by the offline enhancement pipeline.
class OfflineTools {
  const OfflineTools({
    this.ffmpeg,
    this.realEsrgan,
    this.rife,
    this.rifeModel,
  });

  final String? ffmpeg;
  final String? realEsrgan;
  final String? rife;
  final String? rifeModel;

  bool get hasFfmpeg => ffmpeg != null && ffmpeg!.isNotEmpty;
  bool get hasUpscaler => realEsrgan != null && realEsrgan!.isNotEmpty;
  bool get hasInterpolation => rife != null && rife!.isNotEmpty;

  bool get canEnhance => hasFfmpeg && (hasUpscaler || hasInterpolation);

  static Future<OfflineTools> detect({
    ProcessRunner runner = const SystemProcessRunner(),
    String? ffmpegPath,
    String? esrganPath,
    String? rifePath,
  }) async {
    return OfflineTools(
      ffmpeg: _existing(ffmpegPath) ?? await _which('ffmpeg', runner),
      realEsrgan:
          _existing(esrganPath) ?? await _which('realesrgan-ncnn-vulkan', runner),
      rife: _existing(rifePath) ?? await _which('rife-ncnn-vulkan', runner),
    );
  }

  static String? _existing(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    return File(path.trim()).existsSync() ? path.trim() : null;
  }

  static Future<String?> _which(String name, ProcessRunner runner) async {
    try {
      final output = await runner.run('where', [name]);
      if (output.exitCode != 0) return null;
      final line = output.stdout
          .split(RegExp(r'\r?\n'))
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      return line.isEmpty ? null : line;
    } on Exception {
      return null;
    }
  }
}

class OfflineStage {
  const OfflineStage(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

/// Commands for: extract frames -> Real-ESRGAN -> optional RIFE -> encode.
class OfflinePlan {
  OfflinePlan._();

  static List<OfflineStage> build({
    required OfflineTools tools,
    required String input,
    required String output,
    required String workDir,
    int scale = 2,
    int fps = 30,
  }) {
    final frames = '$workDir${_sep}frames';
    final upscaled = '$workDir${_sep}upscaled';
    final interpolated = '$workDir${_sep}interpolated';
    final stages = <OfflineStage>[
      OfflineStage(tools.ffmpeg!, [
        '-y',
        '-i',
        input,
        '-r',
        '$fps',
        '-qscale:v',
        '1',
        '$frames$_sep%08d.png',
      ]),
    ];
    String source = frames;
    if (tools.hasUpscaler) {
      stages.add(OfflineStage(tools.realEsrgan!, [
        '-i',
        frames,
        '-o',
        upscaled,
        '-n',
        'realesr-animevideov3',
        '-s',
        '$scale',
        '-f',
        'png',
      ]));
      source = upscaled;
    }
    if (tools.hasInterpolation) {
      final model = tools.rifeModel ??
          p.join(p.dirname(tools.rife!), 'rife-v4.6');
      stages.add(OfflineStage(tools.rife!, [
        '-i',
        source,
        '-o',
        interpolated,
        '-m',
        model,
      ]));
      source = interpolated;
    }
    stages.add(OfflineStage(tools.ffmpeg!, [
      '-y',
      '-framerate',
      '${fps * (tools.hasInterpolation ? 2 : 1)}',
      '-i',
      '$source$_sep%08d.png',
      '-i',
      input,
      '-map',
      '0:v:0',
      '-map',
      '1:a?',
      '-c:v',
      'libx264',
      '-crf',
      '18',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'copy',
      output,
    ]));
    return stages;
  }

  static String get _sep => Platform.pathSeparator;
}
