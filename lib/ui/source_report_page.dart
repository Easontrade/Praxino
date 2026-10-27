import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/sources/reliability/source_prober.dart';
import '../core/sources/source_report.dart';
import '../core/sources/source_report_runner.dart';

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
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
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
