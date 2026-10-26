import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/enhance/offline/ffmpeg_runner.dart';
import '../core/enhance/offline/gpu_processor.dart';
import '../core/enhance/offline/offline_job.dart';
import '../core/enhance/offline/offline_queue.dart';
import '../core/enhance/offline/offline_tools.dart';
import '../core/settings/settings_store.dart';

class OfflineTasksPage extends StatefulWidget {
  const OfflineTasksPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<OfflineTasksPage> createState() => _OfflineTasksPageState();
}

class _OfflineTasksPageState extends State<OfflineTasksPage> {
  OfflineQueue? _queue;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final tools = await OfflineTools.detect(
      ffmpegPath: widget.settings.offlineFfmpegPath,
      esrganPath: widget.settings.offlineEsrganPath,
      rifePath: widget.settings.offlineRifePath,
    );
    final processor = tools.canEnhance
        ? GpuOfflineProcessor(tools: tools)
        : FfmpegOfflineProcessor(runner: FfmpegRunner());
    if (!mounted) return;
    setState(() {
      _queue = OfflineQueue(
        processor: processor,
        initial: widget.settings.offlineJobs,
        persist: widget.settings.saveOfflineJobs,
      );
    });
  }

  Future<void> _add() async {
    final queue = _queue;
    if (queue == null) return;
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择要离线增强的视频',
    );
    if (result.isEmpty) return;
    for (final file in result) {
      if (file.path != null) queue.add(OfflineJob.forSource(file.path!));
    }
    setState(() {});
  }

  Future<void> _start() async {
    final queue = _queue;
    if (queue == null) return;
    setState(() => _busy = true);
    await queue.start();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    if (queue == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final jobs = queue.jobs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('离线增强任务'),
        actions: [
          IconButton(
            tooltip: '添加视频',
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
          IconButton(
            tooltip: '开始队列',
            icon: const Icon(Icons.play_arrow),
            onPressed: _busy ? null : _start,
          ),
        ],
      ),
      body: jobs.isEmpty
          ? const Center(child: Text('没有任务。添加视频后开始排队。'))
          : ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (context, index) {
                final job = jobs[index];
                return ListTile(
                  leading: Icon(_icon(job.status)),
                  title: Text(job.sourcePath.split(RegExp(r'[\\/]')).last),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_label(job.status)}'
                          '${job.error == null ? '' : ' · ${job.error}'}'),
                      if (job.status == OfflineJobStatus.running)
                        LinearProgressIndicator(value: job.progress),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (job.status == OfflineJobStatus.paused)
                        IconButton(
                          tooltip: '继续',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () {
                            queue.resume(job.id);
                            setState(() {});
                          },
                        ),
                      if (job.status == OfflineJobStatus.running ||
                          job.status == OfflineJobStatus.queued)
                        IconButton(
                          tooltip: '暂停/取消',
                          icon: const Icon(Icons.pause),
                          onPressed: () {
                            queue.pause(job.id);
                            setState(() {});
                          },
                        ),
                      if (job.status == OfflineJobStatus.failed ||
                          job.status == OfflineJobStatus.cancelled)
                        IconButton(
                          tooltip: '重试',
                          icon: const Icon(Icons.refresh),
                          onPressed: () {
                            queue.retry(job.id);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  static String _label(OfflineJobStatus status) => switch (status) {
        OfflineJobStatus.queued => '排队中',
        OfflineJobStatus.running => '处理中',
        OfflineJobStatus.paused => '已暂停',
        OfflineJobStatus.completed => '已完成',
        OfflineJobStatus.failed => '失败',
        OfflineJobStatus.cancelled => '已取消',
      };

  static IconData _icon(OfflineJobStatus status) => switch (status) {
        OfflineJobStatus.queued => Icons.schedule,
        OfflineJobStatus.running => Icons.sync,
        OfflineJobStatus.paused => Icons.pause_circle_outline,
        OfflineJobStatus.completed => Icons.check_circle_outline,
        OfflineJobStatus.failed => Icons.error_outline,
        OfflineJobStatus.cancelled => Icons.cancel_outlined,
      };
}
