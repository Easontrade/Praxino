import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/settings/settings_store.dart';
import '../core/sources/reliability/source_prober.dart';
import '../core/sources/source_report.dart';
import '../core/sources/source_report_runner.dart';
import 'source_report_play.dart';

/// Ranks every source that returned a hit: resolve the first episode, probe the
/// stream, then show playability, quality and the direct link.
class SourceReportPage extends StatefulWidget {
  const SourceReportPage({
    super.key,
    required this.query,
    required this.inputs,
    required this.settings,
    this.probe,
    this.httpClient,
  });

  final String query;
  final List<SourceReportInput> inputs;
  final SettingsStore settings;

  /// Test seams; production uses a real HTTP probe/client.
  final StreamProbe? probe;
  final http.Client? httpClient;

  @override
  State<SourceReportPage> createState() => _SourceReportPageState();
}

class _SourceReportPageState extends State<SourceReportPage> {
  SourceReportRunner? _runner;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _runner?.close();
    super.dispose();
  }

  void _start() {
    _runner?.close();
    final runner = SourceReportRunner(
      query: widget.query,
      inputs: widget.inputs,
      probe: widget.probe,
      httpClient: widget.httpClient,
    );
    _runner = runner;
    unawaited(runner.run(onUpdate: () {
      if (!mounted || _runner != runner) return;
      setState(() {});
    }));
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
    final runner = _runner;
    final entries = runner?.entries ?? const <SourceReportEntry>[];
    final total = runner?.total ?? 0;
    final done = runner?.done ?? 0;
    final running = runner?.running ?? false;
    final progress = total == 0 ? null : done / total;
    final best = SourceReport.bestEntry([
      for (final entry in entries)
        if (entry.watchable) entry,
    ]);
    final watchable = [
      for (final entry in entries)
        if (entry.watchable) entry,
    ];
    final broken = [
      for (final entry in entries)
        if (!entry.watchable) entry,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('源排行 · ${widget.query}'),
        actions: [
          IconButton(
            tooltip: '重新检测',
            onPressed: running ? null : _start,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (best != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => playReportEntry(context, widget.settings, best),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    '播放最佳源：${best.sourceName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          if (running)
            Column(
              children: [
                LinearProgressIndicator(value: progress),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('正在检测 $done / $total 个源'),
                ),
              ],
            ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(running ? '正在解析每个源…' : '没有可检测的结果'),
                  )
                : ListView(
                    children: [
                      for (final entry in watchable) _row(entry),
                      if (broken.isNotEmpty)
                        ExpansionTile(
                          leading:
                              const Icon(Icons.block, color: Colors.red),
                          title: Text('打不开的源（${broken.length}）'),
                          subtitle: const Text('检测时连不上，换一个能看的即可'),
                          children: [for (final entry in broken) _row(entry)],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(SourceReportEntry entry) => ListTile(
        leading: Icon(
          entry.watchable ? Icons.play_circle_outline : Icons.block,
          color: entry.watchable ? Colors.green : Colors.red,
        ),
        title: Text('${entry.sourceName} · ${entry.title}'),
        subtitle: Text(
          entry.quality == '未知' || entry.quality.isEmpty
              ? entry.verdict
              : '${entry.verdict} · ${entry.quality}',
          style: TextStyle(color: entry.watchable ? Colors.green : Colors.red),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.watchable)
              IconButton(
                tooltip: '播放',
                icon: const Icon(Icons.play_arrow),
                onPressed: () =>
                    playReportEntry(context, widget.settings, entry),
              ),
            IconButton(
              tooltip: '复制链接',
              icon: const Icon(Icons.copy),
              onPressed: () => _copy(entry.link),
            ),
          ],
        ),
        onTap: entry.watchable
            ? () => playReportEntry(context, widget.settings, entry)
            : null,
      );
}
