import 'dart:async';

import 'package:flutter/material.dart';

import '../core/settings/settings_store.dart';
import '../core/sources/reliability/http_stream_prober.dart';
import '../core/sources/reliability/source_prober.dart';
import '../core/sources/sniffer/sniffer_coordinator.dart';
import '../core/sources/sniffer/stream_url_matcher.dart';
import '../core/sources/sniffer/webview_sniffer_backend.dart';
import '../core/sources/source_adapter.dart';
import 'player_page.dart';
import 'webview_sniffer_host.dart';

/// Shows the episode groups of one search hit and resolves a chosen episode.
class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({
    super.key,
    required this.adapter,
    required this.media,
    required this.settings,
    this.prober,
    this.autoPlay = false,
  });

  final SourceAdapter adapter;
  final MediaSummary media;
  final SettingsStore settings;
  final SourceProber? prober;

  /// Play the first episode as soon as the episode list loads. Used by the
  /// source ranking so one click on a "需抓流" row starts playback directly.
  final bool autoPlay;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  List<EpisodeGroup>? _groups;
  Object? _error;
  bool _busy = false;
  HttpStreamProber? _httpProber;
  SourceProber? _prober;
  WebViewSnifferBackend? _sniffer;
  bool _sniffing = false;
  bool _autoPlayed = false;

  @override
  void initState() {
    super.initState();
    if (widget.prober != null) {
      _prober = widget.prober;
    } else {
      _httpProber = HttpStreamProber();
      _prober = SourceProber(
        probe: _httpProber!.probe,
        timeout: const Duration(seconds: 5),
      );
    }
    _load();
  }

  @override
  void dispose() {
    _httpProber?.close();
    final sniffer = _sniffer;
    if (sniffer != null) unawaited(sniffer.stop());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _groups = null;
      _error = null;
    });
    try {
      final groups = await widget.adapter.episodes(widget.media);
      if (!mounted) return;
      setState(() => _groups = groups);
      if (widget.autoPlay &&
          !_autoPlayed &&
          groups.isNotEmpty &&
          groups.first.episodes.isNotEmpty) {
        _autoPlayed = true;
        await _play(groups.first.episodes.first);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _play(Episode episode) async {
    setState(() => _busy = true);
    try {
      final streams = await _candidatesFor(episode);
      if (!mounted) return;
      if (streams.isEmpty) {
        _toast('这个源没有返回可播放地址（可能需要 StreamSniffer）');
        return;
      }
      final next = _nextEpisode(episode);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(
          streams: streams,
          settings: widget.settings,
          prefetchNext: next == null ? null : () async {
            final nextStreams = await _candidatesFor(next);
            return nextStreams.isEmpty ? null : nextStreams.first;
          },
        ),
      ));
    } catch (error) {
      _toast('打开失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Episode? _nextEpisode(Episode episode) {
    for (final group in _groups ?? const <EpisodeGroup>[]) {
      final index = group.episodes.indexOf(episode);
      if (index >= 0 && index + 1 < group.episodes.length) {
        return group.episodes[index + 1];
      }
    }
    return null;
  }

  Future<List<PlayableStream>> _candidatesFor(Episode episode) async {
    final groups = _groups ?? const <EpisodeGroup>[];
    var selectedIndex = -1;
    for (final group in groups) {
      final index = group.episodes.indexOf(episode);
      if (index >= 0) {
        selectedIndex = index;
        break;
      }
    }

    final candidates = <Episode>[
      episode,
      for (final group in groups)
        if (selectedIndex >= 0 && selectedIndex < group.episodes.length)
          group.episodes[selectedIndex],
    ];
    final resolved = await Future.wait(candidates.map(_resolve));
    final seen = <String>{};
    final streams = <PlayableStream>[];
    for (final stream in resolved.whereType<PlayableStream>()) {
      if (seen.add(stream.url)) streams.add(stream);
    }
    if (streams.isEmpty) {
      if (isStreamUrl(episode.url)) {
        streams.add(PlayableStream(episode.url));
      } else {
        final sniffed = await _sniff(episode.url);
        if (sniffed != null) streams.add(sniffed);
      }
    }
    final prober = _prober;
    if (prober == null || streams.isEmpty) return streams;
    final results = await prober.probeAll(streams);
    return SourceProber.rank(streams, results);
  }

  Future<PlayableStream?> _sniff(String pageUrl) async {
    if (_sniffing || !mounted) return null;
    _sniffing = true;
    final backend = WebViewSnifferBackend();
    setState(() => _sniffer = backend);
    try {
      // Let WebViewSnifferHost mount before starting the controller.
      await WidgetsBinding.instance.endOfFrame;
      return await SnifferCoordinator(backend: backend).sniff(pageUrl);
    } catch (_) {
      return null;
    } finally {
      await backend.stop();
      if (mounted) setState(() => _sniffer = null);
      _sniffing = false;
    }
  }

  Future<PlayableStream?> _resolve(Episode episode) async {
    try {
      return await widget.adapter
          .resolve(episode)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: _body()),
      ],
    );
    final sniffer = _sniffer;
    return Scaffold(
      appBar: AppBar(title: Text(widget.media.title)),
      body: sniffer == null
          ? content
          : WebViewSnifferHost(backend: sniffer, child: content),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _Message(
        text: '加载剧集失败：$_error',
        action: FilledButton.tonal(
          onPressed: _load,
          child: const Text('重试'),
        ),
      );
    }
    final groups = _groups;
    if (groups == null) return const Center(child: CircularProgressIndicator());
    if (groups.isEmpty) return const _Message(text: '这个源没有返回剧集。');
    return ListView(
      children: [
        for (final group in groups)
          ExpansionTile(
            title: Text(group.name),
            initiallyExpanded: true,
            children: [
              for (final episode in group.episodes)
                ListTile(
                  title: Text(episode.name),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: _busy ? null : () => _play(episode),
                ),
            ],
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      );
}
