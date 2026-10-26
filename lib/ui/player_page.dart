import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../core/enhance/enhance_settings.dart';
import '../core/library/local_files.dart';
import '../core/player/praxino_player.dart';
import '../core/settings/settings_store.dart';
import 'enhance_menu.dart';

/// Plays a list of local files or URLs, starting at [index].
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.sources,
    this.index = 0,
    required this.settings,
  });

  final List<String> sources;
  final int index;
  final SettingsStore settings;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final PraxinoPlayer _player = PraxinoPlayer();
  late String _title = _displayName(widget.sources[widget.index]);

  @override
  void initState() {
    super.initState();
    _player.player.stream.playlist.listen((playlist) {
      if (!mounted || playlist.medias.isEmpty) return;
      final uri = playlist.medias[playlist.index].uri;
      setState(() => _title = _displayName(uri));
      if (!uri.contains('://')) widget.settings.addRecent(uri);
    });
    _start();
  }

  /// File name for local paths, last path segment for URLs.
  static String _displayName(String source) {
    if (!source.contains('://')) return p.basename(source);
    final uri = Uri.tryParse(source);
    final last = uri?.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return last ?? source;
  }

  Future<void> _start() async {
    await _player.setEnhance(widget.settings.enhance);
    await _player.player.open(
      Playlist(widget.sources.map(Media.new).toList(), index: widget.index),
    );
  }

  Future<void> _setEnhance(EnhanceSettings value) async {
    await _player.setEnhance(value);
    await widget.settings.setEnhance(value);
  }

  void _setUpscale(UpscalePreset preset) {
    _setEnhance(_player.enhance.value.copyWith(upscale: preset));
    _toast('超分辨率：${preset.label}');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        width: 280,
      ));
  }

  Future<void> _pickSubtitle() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '加载外挂字幕',
      type: FileType.custom,
      allowedExtensions:
          kSubtitleExtensions.map((e) => e.substring(1)).toList(),
    );
    final path = files.firstOrNull?.path;
    if (path != null) await _loadSubtitle(path);
  }

  Future<void> _loadSubtitle(String path) async {
    await _player.addExternalSubtitle(path);
    _toast('已加载字幕：${p.basename(path)}');
  }

  void _onDrop(DropDoneDetails details) {
    for (final file in details.files) {
      if (isSubtitleFile(file.path)) {
        _loadSubtitle(file.path);
      } else if (isVideoFile(file.path)) {
        final list = siblingVideos(file.path);
        _player.player.open(Playlist(
          list.map(Media.new).toList(),
          index: list.indexOf(file.path).clamp(0, list.length - 1),
        ));
        return;
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
          _setUpscale(UpscalePreset.off),
      const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
          _setUpscale(UpscalePreset.anime4kFast),
      const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
          _setUpscale(UpscalePreset.anime4kBalanced),
      const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
          _setUpscale(UpscalePreset.anime4kQuality),
      const SingleActivator(LogicalKeyboardKey.keyE, control: true): () {
        final e = _player.enhance.value;
        final on = !(e.deband || e.denoise);
        _setEnhance(e.copyWith(deband: on, denoise: on));
        _toast(on ? '画质修复：开（去色带＋降噪）' : '画质修复：关');
      },
    };

    final bar = <Widget>[
      const MaterialDesktopSkipPreviousButton(),
      const MaterialDesktopPlayOrPauseButton(),
      const MaterialDesktopSkipNextButton(),
      const MaterialDesktopVolumeButton(),
      const MaterialDesktopPositionIndicator(),
      const Spacer(),
      MaterialDesktopCustomButton(
        icon: const Icon(Icons.subtitles_outlined),
        onPressed: _pickSubtitle,
      ),
      EnhanceButton(settings: _player.enhance, onChanged: _setEnhance),
      const MaterialDesktopFullscreenButton(),
    ];

    final theme = MaterialDesktopVideoControlsThemeData(
      seekBarPositionColor: Theme.of(context).colorScheme.primary,
      seekBarThumbColor: Theme.of(context).colorScheme.primary,
      bottomButtonBar: bar,
      topButtonBar: [
        MaterialDesktopCustomButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: shortcuts,
        // Keeps keyboard focus inside the player so the bindings above fire
        // even before the controls have been hovered.
        child: Focus(
          autofocus: true,
          child: DropTarget(
            onDragDone: _onDrop,
            child: MaterialDesktopVideoControlsTheme(
              normal: theme,
              fullscreen: theme,
              child: Video(controller: _player.controller),
            ),
          ),
        ),
      ),
    );
  }
}
