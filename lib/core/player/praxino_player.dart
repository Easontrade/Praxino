import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../enhance/compare_state.dart';
import '../enhance/enhance_settings.dart';

/// mpv options every player starts with. Kept close to a hand-tuned
/// standalone mpv.conf so behaviour matches what users already know.
const Map<String, String> kMpvBaseline = {  // Subtitles: pick up `movie.zh.ass` and `subs/` next to the file.
  'sub-auto': 'fuzzy',
  'sub-file-paths': 'subs;subtitles;字幕',
  'embeddedfonts': 'yes',
  'sub-ass-override': 'scale',
  'slang': 'zh-Hans,zh-CN,chs,sc,zh,en,eng',
  'alang': 'ja,jpn,zh,chi,en,eng',
  // Network sources and high-bitrate local files.
  'cache': 'yes',
  'demuxer-max-bytes': '512MiB',
  'demuxer-max-back-bytes': '256MiB',
  'keep-open': 'yes',
  'force-seekable': 'yes',
};

/// A snapshot of mpv's video/performance properties.
class PlaybackStats {
  const PlaybackStats({this.height, this.fps, this.droppedFrames});

  final int? height;
  final double? fps;
  final int? droppedFrames;
}

/// A media_kit [Player] plus the mpv-level features Praxino adds on top.
class PraxinoPlayer {
  PraxinoPlayer()
      : player = Player(
          configuration: const PlayerConfiguration(
            title: 'Praxino',
            libass: true,
            bufferSize: 64 * 1024 * 1024,
            logLevel: MPVLogLevel.warn,
          ),
        ) {
    controller = VideoController(player);
    if (kDebugMode) {
      player.stream.log.listen((l) => debugPrint('[mpv:${l.prefix}] ${l.text}'));
      _startDiagnostics();
    }
    _ready = _applyBaseline();
  }

  Timer? _diagnosticsTimer;

  /// Debug-only: when `PRAXINO_DIAG_LOG` names a file, append mpv log lines
  /// and a playback-stats line every 2 s. Lets windowless runs (no console)
  /// be checked afterwards.
  void _startDiagnostics() {
    final path = Platform.environment['PRAXINO_DIAG_LOG'];
    if (path == null || path.isEmpty) return;
    final file = File(path);
    void write(String line) {
      try {
        file.writeAsStringSync('${DateTime.now().toIso8601String()} $line\n',
            mode: FileMode.append, flush: true);
      } on FileSystemException {
        // Best-effort diagnostics only.
      }
    }

    player.stream.log.listen((l) => write('[mpv:${l.prefix}] ${l.text}'));
    // mpv's own verbose log is written synchronously, so it survives crashes
    // inside native filters.
    _native.setProperty('log-file', '$path.mpv.log');
    _diagnosticsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final stats = await playbackStats();
      final vf = await _native.getProperty('vf');
      write('[stats] height=${stats.height} fps=${stats.fps} '
          'dropped=${stats.droppedFrames} vf=$vf');
    });
  }

  final Player player;
  late final VideoController controller;
  late final Future<void> _ready;

  final ValueNotifier<EnhanceSettings> enhance =
      ValueNotifier(const EnhanceSettings());
  final CompareState _compare = CompareState();
  String? _vapoursynthScript;

  bool get comparing => _compare.active;

  NativePlayer get _native => player.platform as NativePlayer;

  Future<void> _applyBaseline() async {
    for (final e in kMpvBaseline.entries) {
      // Path lists are written with `;` above; mpv wants `:` outside Windows.
      final value = e.key == 'sub-file-paths' && !Platform.isWindows
          ? e.value.replaceAll(';', ':')
          : e.value;
      await _native.setProperty(e.key, value);
    }
  }

  Future<void> open(String source, {Map<String, String>? httpHeaders}) async {
    await _ready;
    await player.open(Media(source, httpHeaders: httpHeaders));
  }

  /// Applies [settings] to the running player. Safe to call mid-playback.
  ///
  /// While hold-to-compare is active the change is remembered for restore
  /// instead of applying on top of the comparison.
  Future<void> setEnhance(
    EnhanceSettings settings, {
    String? vapoursynthScript,
  }) async {
    _vapoursynthScript = vapoursynthScript;
    if (_compare.active) {
      _compare.noteSettingsChange(settings);
      return;
    }
    await _applyEnhance(settings);
  }

  /// Hold-to-compare: temporarily show the original picture.
  Future<void> beginCompare() async {
    final off = _compare.begin(enhance.value);
    if (off != null) await _applyEnhance(off, withScript: false);
  }

  Future<void> endCompare() async {
    final saved = _compare.end();
    if (saved != null) await _applyEnhance(saved);
  }

  Future<void> _applyEnhance(
    EnhanceSettings settings, {
    bool withScript = true,
  }) async {
    await _ready;
    var script = withScript ? _vapoursynthScript : null;
    if (script != null && script.isNotEmpty) {
      // mpv's filter parser treats ':' as an option separator, so pass a bare
      // file name from the executable directory instead of a Windows path.
      try {
        final target = p.join(
          p.dirname(Platform.resolvedExecutable),
          '.praxino-vs.vpy',
        );
        await File(script).copy(target);
        script = p.basename(target);
      } on FileSystemException {
        // Fall back to the original path; the filter will report the error.
      }
    }
    final props = settings.toMpvProperties(
      shaderDir: shaderDirectoryFor(settings.upscale),
      listSeparator: Platform.isWindows ? ';' : ':',
      vapoursynthScript: script,
      denoiseShader: settings.denoise
          ? p.join(shaderRoot, 'denoise.glsl').replaceAll('\\', '/')
          : null,
    );
    for (final e in props.entries) {
      await _native.setProperty(e.key, e.value);
    }
    enhance.value = settings;
    if (kDebugMode) {
      final vf = props['vf'] ?? '';
      try {
        File('${Directory.systemTemp.path}${Platform.pathSeparator}'
                'praxino-enhance.log')
            .writeAsStringSync(
          '${DateTime.now().toIso8601String()} vf=$vf\n',
          mode: FileMode.append,
          flush: true,
        );
      } on FileSystemException {
        // Best-effort diagnostics only.
      }
      final active = await _native.getProperty('glsl-shaders');
      debugPrint('[enhance] ${settings.toJson()} vf=$vf shaders=$active');
    }
  }

  Future<void> addExternalSubtitle(String path) =>
      player.setSubtitleTrack(SubtitleTrack.uri(path, title: p.basename(path)));

  Future<PlaybackStats> playbackStats() async {
    await _ready;
    return PlaybackStats(
      height: int.tryParse(await _native.getProperty('video-params/h')),
      fps: double.tryParse(await _native.getProperty('estimated-vf-fps')),
      droppedFrames:
          int.tryParse(await _native.getProperty('frame-drop-count')),
    );
  }

  /// Attaches a separate audio URL (mpv `audio-files`), or clears it.
  Future<void> setAudioFile(String? url) async {
    await _ready;
    await _native.setProperty('audio-files', url ?? '');
  }

  Future<void> setAudioTrack(String id) async {
    await _ready;
    await player.setAudioTrack(AudioTrack(id, null, null));
  }

  /// Selects a subtitle track by id, or turns subtitles off when [id] is null.
  Future<void> setSubtitleTrack(String? id) async {
    await _ready;
    await player.setSubtitleTrack(
      id == null ? SubtitleTrack.no() : SubtitleTrack(id, null, null),
    );
  }

  /// Selects the secondary subtitle track (mpv `secondary-sid`), or off.
  Future<void> setSecondarySubtitle(String? id) async {
    await _ready;
    await _native.setProperty('secondary-sid', id ?? 'no');
  }

  /// Moves mpv's subtitle delay by [delta] seconds, clamped to ±10s.
  Future<double> adjustSubtitleDelay(double delta) async {
    await _ready;
    final raw = await _native.getProperty('sub-delay');
    final current = double.tryParse(raw) ?? 0;
    final next = (current + delta).clamp(-10.0, 10.0).toDouble();
    await _native.setProperty('sub-delay', next.toStringAsFixed(2));
    return next;
  }

  /// Changes playback speed by [delta], clamped to 0.25x–4x.
  Future<double> adjustSpeed(double delta) async {
    await _ready;
    final next = (player.state.rate + delta).clamp(0.25, 4.0).toDouble();
    await player.setRate(next);
    return next;
  }

  /// Saves a PNG screenshot under `Pictures/Praxino` and returns the folder.
  Future<String> screenshot() async {
    await _ready;
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final dir = Directory(p.join(home, 'Pictures', 'Praxino'));
    await dir.create(recursive: true);
    await _native.setProperty('screenshot-directory', dir.path);
    await _native.setProperty('screenshot-format', 'png');
    await _native.command(['screenshot']);
    return dir.path;
  }

  /// Root directory of the bundled shader families at runtime.
  static String get shaderRoot {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p
        .join(exeDir, 'data', 'flutter_assets', 'assets', 'shaders')
        .replaceAll('\\', '/');
  }

  /// Directory that holds the bundled VapourSynth `.vpy` templates.
  static String get vapoursynthTemplateDirectory => p.join(
      p.dirname(Platform.resolvedExecutable),
      'data', 'flutter_assets', 'assets', 'vapoursynth');

  /// Directory that holds [preset]'s shader files.
  static String shaderDirectoryFor(UpscalePreset preset) =>
      p.join(shaderRoot, preset.shaderFamily).replaceAll('\\', '/');

  Future<void> dispose() async {
    _diagnosticsTimer?.cancel();
    enhance.dispose();
    await player.dispose();
  }
}
