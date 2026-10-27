import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/sources/reliability/http_stream_prober.dart';
import '../core/sources/reliability/source_prober.dart';
import '../core/sources/reliability/title_match.dart';
import '../core/sources/source_adapter.dart';
import '../core/sources/source_report.dart';

/// Ranks every source that returned a hit: resolve the first episode, probe the
/// stream, then show playability, quality and the direct link.
class SourceReportPage extends StatefulWidget {
  const SourceReportPage({
    super.key,
    required this.query,
    required this.inputs,
    this.probe,
    this.httpClient,
  });

  final String query;
  final List<SourceReportInput> inputs;

  /// Test seams; production uses a real HTTP probe/client.
  final StreamProbe? probe;
  final http.Client? httpClient;

  @override
  State<SourceReportPage> createState() => _SourceReportPageState();
}

class _SourceReportPageState extends State<SourceReportPage> {
  final List<SourceReportEntry> _entries = [];
  late final StreamProbe _probe;
  late final http.Client _http;
  HttpStreamProber? _prober;
  late final bool _ownsClient;
  int _total = 0;
  int _done = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _prober = widget.probe == null ? HttpStreamProber() : null;
    _probe = widget.probe ?? _prober!.probe;
    _http = widget.httpClient ?? http.Client();
    _ownsClient = widget.httpClient == null;
    _total = widget.inputs.fold(0, (sum, input) => sum + input.items.length);
    unawaited(_run());
  }

  @override
  void dispose() {
    _prober?.close();
    if (_ownsClient) _http.close();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _done = 0;
      _entries.clear();
    });
    final tasks = <Future<void> Function()>[];
    for (final input in widget.inputs) {
      for (final media in input.items) {
        tasks.add(() => _check(input.adapter, media));
      }
    }
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= tasks.length) return;
        await tasks[index]();
      }
    }

    await Future.wait(List.generate(tasks.length < 5 ? tasks.length : 5, (_) => worker()));
    if (mounted) setState(() => _running = false);
  }

  Future<void> _check(SourceAdapter adapter, MediaSummary media) async {
    SourceReportEntry entry;
    try {
      final groups = await adapter
          .episodes(media)
          .timeout(const Duration(seconds: 12));
      if (groups.isEmpty || groups.first.episodes.isEmpty) {
        entry = SourceReportEntry(
          sourceName: adapter.name,
          title: media.title,
          link: media.url,
          status: SourceReportStatus.unresolved,
          quality: '未知',
          matchScore: TitleMatcher.score(widget.query, media.title).score,
          detail: '没有解析到剧集',
        );
      } else {
        final episode = groups.first.episodes.first;
        PlayableStream? stream;
        try {
          stream = await adapter
              .resolve(episode)
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          stream = null;
        }
        if (stream == null ||
            SourceReport.looksLikeLandingPage(stream.url)) {
          entry = SourceReportEntry(
            sourceName: adapter.name,
            title: media.title,
            link: stream?.url ?? episode.url,
            status: SourceReportStatus.unresolved,
            quality: '未知',
            matchScore: TitleMatcher.score(widget.query, media.title).score,
            detail: stream == null
                ? '需要 WebView 抓流；从搜索结果打开这一集会继续解析'
                : '这是播放页而不是直链，需要 WebView 抓流',
          );
        } else {
          final hls = await _hlsResolution(stream);
          final probe = await _probe(stream);
          final quality = SourceReport.qualityOf(
            height: stream.height,
            width: stream.width,
            title: '${media.title} ${episode.name}',
            url: stream.url,
            hlsResolution: hls,
          );
          entry = SourceReportEntry(
            sourceName: adapter.name,
            title: media.title,
            link: stream.url,
            status: probe.reachable
                ? SourceReportStatus.reachable
                : SourceReportStatus.unreachable,
            quality: quality,
            matchScore: TitleMatcher.score(widget.query, media.title).score,
            latency: probe.latency,
            detail: probe.reachable ? '' : '${probe.error ?? '无法连接'}',
          );
        }
      }
    } catch (error) {
      entry = SourceReportEntry(
        sourceName: adapter.name,
        title: media.title,
        link: media.url,
        status: SourceReportStatus.unreachable,
        quality: '未知',
        matchScore: TitleMatcher.score(widget.query, media.title).score,
        detail: '$error',
      );
    }
    if (!mounted) return;
    setState(() {
      _entries.add(entry);
      _done++;
      SourceReport.sort(_entries);
    });
  }

  Future<String?> _hlsResolution(PlayableStream stream) async {
    if (!stream.url.toLowerCase().contains('.m3u8')) return null;
    try {
      final response = await _http.get(
        Uri.parse(stream.url),
        headers: {...stream.headers, 'Range': 'bytes=0-131071'},
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) return null;
      final body = response.body;
      if (!body.contains('#EXTM3U')) return null;
      int? best;
      for (final match
          in RegExp(r'RESOLUTION=(\d+)x(\d+)').allMatches(body)) {
        final height = int.tryParse(match.group(2)!);
        if (height != null && (best == null || height > best)) best = height;
      }
      return best == null ? null : '0x$best';
    } catch (_) {
      return null;
    }
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('链接已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0 ? null : _done / _total;
    return Scaffold(
      appBar: AppBar(
        title: Text('源排行 · ${widget.query}'),
        actions: [
          IconButton(
            tooltip: '重新检测',
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_running)
            Column(
              children: [
                LinearProgressIndicator(value: progress),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('正在检测 $_done / $_total 个源'),
                ),
              ],
            ),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(_running ? '正在解析每个源…' : '没有可检测的结果'),
                  )
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      final color = switch (entry.status) {
                        SourceReportStatus.reachable => Colors.green,
                        SourceReportStatus.unresolved => Colors.amber,
                        SourceReportStatus.unreachable => Colors.red,
                      };
                      final latency = entry.latency == null
                          ? ''
                          : ' · ${entry.latency!.inMilliseconds} ms';
                      final detail =
                          entry.detail.isEmpty ? '' : ' · ${entry.detail}';
                      return ListTile(
                        leading: Icon(
                          switch (entry.status) {
                            SourceReportStatus.reachable =>
                              Icons.check_circle_outline,
                            SourceReportStatus.unresolved => Icons.travel_explore,
                            SourceReportStatus.unreachable =>
                              Icons.error_outline,
                          },
                          color: color,
                        ),
                        title: Text('${entry.sourceName} · ${entry.title}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.statusLabel} · ${entry.quality}$latency$detail',
                              style: TextStyle(color: color),
                            ),
                            SelectableText(
                              entry.link,
                              maxLines: 2,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: '复制链接',
                          icon: const Icon(Icons.copy),
                          onPressed: () => _copy(entry.link),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
