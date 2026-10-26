import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../enhance/enhance_settings.dart';

/// mpv options every player starts with. Kept close to a hand-tuned
/// standalone mpv.conf so behaviour matches what users already know.
const Map<String, String> kMpvBaseline = {
  // Subtitles: pick up `movie.zh.ass` and `subs/` next to the file.
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
    }
    _ready = _applyBaseline();
  }

  final Player player;
  late final VideoController controller;
  late final Future<void> _ready;

  final ValueNotifier<EnhanceSettings> enhance =
      ValueNotifier(const EnhanceSettings());

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
  Future<void> setEnhance(EnhanceSettings settings) async {
    await _ready;
    final props = settings.toMpvProperties(
      shaderDir: shaderDirectory,
      listSeparator: Platform.isWindows ? ';' : ':',
    );
    for (final e in props.entries) {
      await _native.setProperty(e.key, e.value);
    }
    enhance.value = settings;
    if (kDebugMode) {
      final active = await _native.getProperty('glsl-shaders');
      debugPrint('[enhance] ${settings.toJson()} shaders=$active');
    }
  }

  Future<void> addExternalSubtitle(String path) =>
      player.setSubtitleTrack(SubtitleTrack.uri(path, title: p.basename(path)));

  /// Directory that holds the bundled Anime4K shaders at runtime.
  ///
  /// Flutter desktop copies assets next to the executable, so mpv can read
  /// them straight from disk.
  static String get shaderDirectory {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p
        .join(exeDir, 'data', 'flutter_assets', 'assets', 'shaders', 'anime4k')
        .replaceAll('\\', '/');
  }

  Future<void> dispose() async {
    enhance.dispose();
    await player.dispose();
  }
}
