import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../core/danmaku/danmaku_engine.dart';
import '../core/danmaku/danmaku_service.dart';
import '../core/enhance/enhance_advisor.dart';
import '../core/enhance/enhance_settings.dart';
import '../core/enhance/interpolation.dart';
import '../core/library/local_files.dart';
import '../core/library/watch_history.dart';
import '../core/player/praxino_player.dart';
import '../core/settings/keybindings.dart';
import '../core/settings/settings_store.dart';
import '../core/sources/reliability/auto_switch.dart';
import '../core/sources/reliability/prefetch_controller.dart';
import '../core/sources/source_adapter.dart';
import 'enhance_menu.dart';
import 'danmaku/danmaku_overlay.dart';
import 'key_chord_ui.dart';
import 'playlist_panel.dart';
import 'subtitle_search_dialog.dart';
import 'track_menu.dart';

/// Plays a list of local files or URLs, starting at [index].
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    this.sources = const [],
    this.index = 0,
    required this.settings,
    this.headers = const {},
    this.audioUrl,
    this.streams = const [],
    this.prefetchNext,
    this.onProgress,
    this.startPosition = Duration.zero,
  });

  final List<String> sources;
  final int index;
  final SettingsStore settings;

  /// HTTP headers for the whole playlist, e.g. a source's Referer/Cookie.
  final Map<String, String> headers;

  /// Separate audio URL for sources that return video-only + audio-only.
  final String? audioUrl;

  /// Online candidates for one episode, tried in order when playback fails.
  final List<PlayableStream> streams;

  /// Resolves the next episode's stream for prefetching, if there is one.
  final Future<PlayableStream?> Function()? prefetchNext;

  /// Reports playback position for remote servers (Jellyfin/Emby).
  final void Function(Duration position)? onProgress;

  /// Resume position for remote streams opened directly.
  final Duration startPosition;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final PraxinoPlayer _player = PraxinoPlayer();
  late String _title = widget.streams.isNotEmpty
      ? _displayName(widget.streams.first.url)
      : widget.sources.isEmpty
          ? 'Praxino'
          : _displayName(widget.sources[widget.index]);
  late final WatchHistory _history;
  late final Keybindings _keys;
  Timer? _historyTimer;
  Timer? _watchdog;
  Timer? _advisorTimer;
  final EnhanceAdvisor _advisor = EnhanceAdvisor();
  final DanmakuEngine _danmakuEngine = DanmakuEngine();
  final ValueNotifier<List<DanmakuItem>> _danmakuItems =
      ValueNotifier(const []);
  late final DanmakuService _danmakuService;
  int _danmakuRequest = 0;
  bool _startPositionApplied = false;
  bool _checkingPerformance = false;
  AutoSwitch? _auto;
  PrefetchController<PlayableStream?>? _prefetch;
  bool _advancing = false;
  Duration _lastPosition = Duration.zero;
  DateTime _lastProgress = DateTime.now();
  bool _switching = false;
  bool _exhausted = false;
  String? _secondarySubtitle;
  bool _playlistOpen = false;

  @override
  void initState() {
    super.initState();
    _history = widget.settings.watchHistory;
    _keys = widget.settings.keybindings;
    _danmakuService = DanmakuService(settings: widget.settings);
    _player.player.stream.playlist.listen((playlist) {
      if (!mounted || playlist.medias.isEmpty) return;
      final uri = playlist.medias[playlist.index].uri;
      _secondarySubtitle = null;
      setState(() => _title = _displayName(uri));
      if (uri.contains('://')) {
        _danmakuRequest++;
        _danmakuItems.value = const [];
      } else {
        widget.settings.addRecent(uri);
        unawaited(_loadDanmaku(uri));
      }
      unawaited(_player.setSecondarySubtitle(null));
    });
    _historyTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
    _advisorTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _checkPerformance());
    if (widget.streams.isNotEmpty) {
      _auto = AutoSwitch(candidates: widget.streams);
      if (widget.prefetchNext != null) {
        _prefetch = PrefetchController(load: widget.prefetchNext!);
      }
      _player.player.stream.error
          .listen((_) => unawaited(_switchNext(hadError: true)));
      _player.player.stream.completed.listen((done) {
        if (done) unawaited(_advanceToNext());
      });
      _watchdog =
          Timer.periodic(const Duration(seconds: 1), (_) => _watchdogTick());
    }
    _start();
  }

  /// File name for local paths, last path segment for URLs.
  static String _displayName(String source) {
    if (!source.contains('://')) return p.basename(source);
    final uri = Uri.tryParse(source);
    final last = uri?.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return last ?? source;
  }

  Future<void> _loadDanmaku(String path) async {
    final request = ++_danmakuRequest;
    final items = await _danmakuService.forLocalFile(path);
    if (!mounted || request != _danmakuRequest) return;
    _danmakuItems.value = items ?? const [];
  }

  /// Bundled template for the chosen interpolation mode, unless the user
  /// configured their own script in settings.
  String? _scriptFor(EnhanceSettings value) => interpolationScriptFor(
        value.interpolation,
        templateDir: PraxinoPlayer.vapoursynthTemplateDirectory,
        override: widget.settings.interpolationScriptPath,
        profile: value.rifeProfile,
      );

  Future<void> _start() async {
    await _player.setEnhance(
      widget.settings.enhance,
      vapoursynthScript: _scriptFor(widget.settings.enhance),
    );
    if (widget.streams.isNotEmpty) {
      await _openStream(widget.streams.first);
      return;
    }
    await _player.setAudioFile(widget.audioUrl);
    await _player.player.open(
      Playlist(
        [
          for (final source in widget.sources)
            Media(
              source,
              httpHeaders:
                  widget.headers.isEmpty ? null : widget.headers,
            ),
        ],
        index: widget.index,
      ),
    );
    await _restorePosition();
  }

  Future<void> _openStream(PlayableStream stream) async {
    await _player.setAudioFile(stream.audioUrl);
    await _player.player.open(Media(
      stream.url,
      httpHeaders: stream.headers.isEmpty ? null : stream.headers,
    ));
    final subtitle = stream.subtitleUrls.values.firstOrNull;
    if (subtitle != null) {
      try {
        await _player.addExternalSubtitle(subtitle);
      } catch (_) {
        // A missing subtitle must not interrupt playback.
      }
    }
    if (!_startPositionApplied && widget.startPosition > Duration.zero) {
      _startPositionApplied = true;
      await _player.player.seek(widget.startPosition);
    }
  }

  Future<void> _switchNext({required bool hadError}) async {
    final auto = _auto;
    if (auto == null || _switching || _exhausted) return;
    final next = auto.trySwitch(
      stalledFor: DateTime.now().difference(_lastProgress),
      hadError: hadError,
    );
    if (next == null) {
      if (!auto.hasNext) {
        _exhausted = true;
        _toast('没有可用线路了');
      }
      return;
    }

    _switching = true;
    final position = _player.player.state.position;
    try {
      await _openStream(next);
      if (position > Duration.zero) {
        await _player.player.seek(position);
      }
      _lastPosition = position;
      _lastProgress = DateTime.now();
      _toast('已切换到备用线路');
    } finally {
      _switching = false;
    }
  }

  Future<void> _advanceToNext() async {
    if (_advancing) return;
    final next = _prefetch?.value;
    if (next == null) return;
    _advancing = true;
    try {
      await _openStream(next);
      _auto = null;
      _prefetch = null;
    } finally {
      _advancing = false;
    }
  }

  void _watchdogTick() {
    final position = _player.player.state.position;
    final duration = _player.player.state.duration;
    final prefetch = _prefetch;
    if (prefetch != null) {
      unawaited(prefetch.onPosition(position, duration));
    }

    final auto = _auto;
    if (auto == null || _switching || _exhausted) return;
    if (position != _lastPosition) {
      _lastPosition = position;
      _lastProgress = DateTime.now();
      return;
    }
    if (!_player.player.state.buffering) return;
    if (!auto.policy.shouldSwitch(
      stalledFor: DateTime.now().difference(_lastProgress),
      hadError: false,
    )) {
      return;
    }
    unawaited(_switchNext(hadError: false));
  }

  String? get _currentSource {
    final playlist = _player.player.state.playlist;
    if (playlist.medias.isEmpty) return null;
    final index = playlist.index.clamp(0, playlist.medias.length - 1);
    return playlist.medias[index].uri;
  }

  Future<void> _restorePosition() async {
    final source = _currentSource;
    if (source == null || source.contains('://')) return;
    final point = _history.find(source);
    if (point == null || !point.shouldResume) return;
    // The duration stream is broadcast without replay, so poll the state
    // instead of waiting for an event that may already have fired during open.
    final duration = await _waitForDuration();
    if (!mounted || duration <= Duration.zero) return;
    await _player.player.seek(point.position);
    if (!mounted) return;
    _toastResume(point.position);
  }

  Future<Duration> _waitForDuration() async {
    for (var attempt = 0; attempt < 50; attempt++) {
      if (!mounted) return Duration.zero;
      final duration = _player.player.state.duration;
      if (duration > Duration.zero) return duration;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return Duration.zero;
  }

  void _savePosition() {
    final source = _currentSource;
    if (source == null) return;
    final position = _player.player.state.position;
    if (position > Duration.zero) widget.onProgress?.call(position);
    if (source.contains('://')) return;
    final duration = _player.player.state.duration;
    if (duration <= Duration.zero || position <= Duration.zero) return;
    if (duration - position <= WatchPoint.keepBeforeEnd) {
      _history.remove(source);
    } else {
      _history.record(WatchPoint(
        path: source,
        position: position,
        duration: duration,
        updatedAt: DateTime.now(),
      ));
    }
    unawaited(widget.settings.saveWatchHistory(_history));
  }

  void _toastResume(Duration position) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('已从 ${_formatDuration(position)} 继续'),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        width: 320,
        action: SnackBarAction(
          label: '从头播放',
          onPressed: () => _player.player.seek(Duration.zero),
        ),
      ));
  }

  static String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<void> _setEnhance(EnhanceSettings value, {bool byUser = true}) async {
    if (byUser) _advisor.noteUserChoice(DateTime.now());
    await _player.setEnhance(
      value,
      vapoursynthScript: _scriptFor(value),
    );
    if (!_player.comparing) {
      await widget.settings.setEnhance(value);
    }
  }

  Future<void> _endCompare() async {
    await _player.endCompare();
    if (mounted) await widget.settings.setEnhance(_player.enhance.value);
  }

  KeyEventResult _onCompareKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.keyC) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      unawaited(_player.beginCompare());
      _toast('对比：原始画面（松开 C 恢复）');
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      unawaited(_endCompare());
      _toast('已恢复画质增强');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _checkPerformance() async {
    if (_checkingPerformance) return;
    _checkingPerformance = true;
    try {
      final stats = await _player.playbackStats();
      if (!mounted || stats.height == null || stats.height == 0) return;
      final current = _player.enhance.value;
      final nextInterpolation = _advisor.evaluateInterpolation(
        current: current.interpolation,
        droppedFrames: stats.droppedFrames ?? 0,
        fps: stats.fps ?? 0,
        now: DateTime.now(),
      );
      if (nextInterpolation != null &&
          nextInterpolation != current.interpolation) {
        await _setEnhance(
          current.copyWith(interpolation: nextInterpolation),
          byUser: false,
        );
        if (mounted) {
          _showDownshiftToast(
            '掉帧过多，补帧已降到：${_interpolationLabel(nextInterpolation)}',
            current,
          );
        }
        return;
      }
      final next = _advisor.evaluate(
        current: current.upscale,
        droppedFrames: stats.droppedFrames ?? 0,
        fps: stats.fps ?? 0,
        now: DateTime.now(),
      );
      if (next == null || next == current.upscale) return;
      await _setEnhance(current.copyWith(upscale: next), byUser: false);
      if (mounted) {
        _showDownshiftToast('掉帧过多，已降到：${next.label}', current);
      }
    } catch (_) {
      // The property may be missing while files change; retry on the next tick.
    } finally {
      _checkingPerformance = false;
    }
  }

  void _setUpscale(UpscalePreset preset) {
    _setEnhance(_player.enhance.value.copyWith(upscale: preset));
    _toast('超分辨率：${preset.label}');
  }

  static String _interpolationLabel(InterpolationMode mode) => switch (mode) {
        InterpolationMode.rife => 'RIFE',
        InterpolationMode.mvtools => 'mvtools',
        InterpolationMode.off => '关闭',
      };

  void _showDownshiftToast(String text, EnhanceSettings previous) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (!mounted) return;
            _setEnhance(previous);
          },
        ),
      ));
  }

  void _togglePlaylist() {
    if (_player.player.state.playlist.medias.isEmpty) return;
    setState(() => _playlistOpen = !_playlistOpen);
  }

  Map<PlayerAction, VoidCallback> _shortcutActions() => {
        PlayerAction.upscaleOff: () => _setUpscale(UpscalePreset.off),
        PlayerAction.upscaleFast: () => _setUpscale(UpscalePreset.anime4kFast),
        PlayerAction.upscaleBalanced: () =>
            _setUpscale(UpscalePreset.anime4kBalanced),
        PlayerAction.upscaleQuality: () =>
            _setUpscale(UpscalePreset.anime4kQuality),
        PlayerAction.toggleEnhance: () {
          final e = _player.enhance.value;
          final on = !(e.deband || e.denoise);
          _setEnhance(e.copyWith(deband: on, denoise: on));
          _toast(on ? '画质修复：开（去色带＋降噪）' : '画质修复：关');
        },
        PlayerAction.subtitleDelayDown: () => _nudgeSubtitleDelay(-0.1),
        PlayerAction.subtitleDelayUp: () => _nudgeSubtitleDelay(0.1),
        PlayerAction.speedDown: () => _nudgeSpeed(-0.1),
        PlayerAction.speedUp: () => _nudgeSpeed(0.1),
        PlayerAction.screenshot: () => _takeScreenshot(),
        PlayerAction.togglePlaylist: _togglePlaylist,
      };

  Future<void> _nudgeSubtitleDelay(double delta) async {
    final next = await _player.adjustSubtitleDelay(delta);
    if (!mounted) return;
    _toast('字幕延迟：${next >= 0 ? '+' : ''}${next.toStringAsFixed(1)}s');
  }

  Future<void> _nudgeSpeed(double delta) async {
    final next = await _player.adjustSpeed(delta);
    if (!mounted) return;
    _toast('播放速度：${next.toStringAsFixed(1)}x');
  }

  Future<void> _takeScreenshot() async {
    await _player.screenshot();
    if (!mounted) return;
    _toast('截图已保存到 图片/Praxino');
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

  Future<void> _searchOnlineSubtitle() async {
    final source = _currentSource;
    if (source == null || source.contains('://')) {
      _toast('在线字幕搜索只支持本地文件');
      return;
    }
    final path = await showDialog<String>(
      context: context,
      builder: (context) => SubtitleSearchDialog(
        videoPath: source,
        title: p.basenameWithoutExtension(source),
        settings: widget.settings,
      ),
    );
    if (path != null) await _loadSubtitle(path);
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

  Widget _buildTrackMenu() {
    return StreamBuilder<Tracks>(
      stream: _player.player.stream.tracks,
      initialData: _player.player.state.tracks,
      builder: (context, tracksSnapshot) {
        final tracks = tracksSnapshot.data ?? _player.player.state.tracks;
        return StreamBuilder<Track>(
          stream: _player.player.stream.track,
          initialData: _player.player.state.track,
          builder: (context, trackSnapshot) {
            final current = trackSnapshot.data ?? _player.player.state.track;
            final subtitleId = current.subtitle.id;
            return TrackMenu(
              audio: [
                for (var i = 0; i < tracks.audio.length; i++)
                  TrackOption(
                    id: tracks.audio[i].id,
                    label: _audioLabel(tracks.audio[i], i),
                  ),
              ],
              subtitles: [
                for (var i = 0; i < tracks.subtitle.length; i++)
                  TrackOption(
                    id: tracks.subtitle[i].id,
                    label: _subtitleLabel(tracks.subtitle[i], i),
                  ),
              ],
              selectedAudio:
                  current.audio.id == 'no' ? null : current.audio.id,
              selectedSubtitle: subtitleId == 'no' || subtitleId == 'auto'
                  ? null
                  : subtitleId,
              selectedSecondary: _secondarySubtitle,
              onAudio: (id) => unawaited(_player.setAudioTrack(id)),
              onSubtitle: (id) => unawaited(_player.setSubtitleTrack(id)),
              onSecondary: (id) {
                setState(() => _secondarySubtitle = id);
                unawaited(_player.setSecondarySubtitle(id));
              },
            );
          },
        );
      },
    );
  }

  static String _audioLabel(AudioTrack track, int index) =>
      track.title ?? track.language ?? '音轨 ${index + 1}';

  static String _subtitleLabel(SubtitleTrack track, int index) =>
      track.title ?? track.language ?? '字幕 ${index + 1}';

  @override
  void dispose() {
    _historyTimer?.cancel();
    _watchdog?.cancel();
    _advisorTimer?.cancel();
    _danmakuRequest++;
    _danmakuService.close();
    _danmakuItems.dispose();
    _savePosition();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, VoidCallback>{};
    for (final entry in _shortcutActions().entries) {
      final chord = _keys.chordFor(entry.key);
      final activator = chord == null ? null : activatorFor(chord);
      if (activator != null) shortcuts[activator] = entry.value;
    }

    final bar = <Widget>[
      const MaterialDesktopSkipPreviousButton(),
      const MaterialDesktopPlayOrPauseButton(),
      const MaterialDesktopSkipNextButton(),
      const MaterialDesktopVolumeButton(),
      const MaterialDesktopPositionIndicator(),
      const Spacer(),
      _buildTrackMenu(),
      MaterialDesktopCustomButton(
        icon: const Icon(Icons.playlist_play),
        onPressed: _togglePlaylist,
      ),
      MaterialDesktopCustomButton(
        icon: const Icon(Icons.subtitles_outlined),
        onPressed: _pickSubtitle,
      ),
      MaterialDesktopCustomButton(
        icon: const Icon(Icons.travel_explore),
        onPressed: _searchOnlineSubtitle,
      ),
      EnhanceButton(
        settings: _player.enhance,
        onChanged: (value) => _setEnhance(value),
      ),
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
          onKeyEvent: _onCompareKey,
          onFocusChange: (hasFocus) {
            if (!hasFocus && _player.comparing) unawaited(_endCompare());
          },
          child: DropTarget(
            onDragDone: _onDrop,
            child: MaterialDesktopVideoControlsTheme(
              normal: theme,
              fullscreen: theme,
              child: Row(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Video(controller: _player.controller),
                        ),
                        Positioned.fill(
                          child: DanmakuOverlay(
                            position: _player.player.stream.position,
                            items: _danmakuItems,
                            engine: _danmakuEngine,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_playlistOpen)
                    PlaylistPanel(
                      titles: [
                        for (final media
                            in _player.player.state.playlist.medias)
                          _displayName(media.uri),
                      ],
                      currentIndex: _player.player.state.playlist.index,
                      onSelected: (index) =>
                          unawaited(_player.player.jump(index)),
                      onClose: () => setState(() => _playlistOpen = false),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
