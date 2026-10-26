import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/library/local_files.dart';
import '../core/settings/settings_store.dart';
import 'player_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings, this.initialSource});

  final SettingsStore settings;

  /// Opened straight away, e.g. from the command line.
  final String? initialSource;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    final source = widget.initialSource;
    if (source != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) =>
          source.contains('://') ? _play([source]) : _playLocal(source));
    }
  }

  Future<void> _play(List<String> sources, [int index = 0]) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        sources: sources,
        index: index,
        settings: widget.settings,
      ),
    ));
    if (mounted) setState(() {}); // refresh recent list
  }

  void _playLocal(String file) {
    final list = siblingVideos(file);
    _play(list, list.indexOf(file).clamp(0, list.length - 1));
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '打开视频',
      type: FileType.custom,
      allowedExtensions: kVideoExtensions.map((e) => e.substring(1)).toList(),
    );
    final path = files.firstOrNull?.path;
    if (path != null) _playLocal(path);
  }

  Future<void> _openUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开链接'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'https://…/video.m3u8 或 .mp4',
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('播放'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url != null && url.trim().isNotEmpty) _play([url.trim()]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recent =
        widget.settings.recent.where((f) => File(f).existsSync()).toList();

    return Scaffold(
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          final video =
              details.files.map((f) => f.path).where(isVideoFile).firstOrNull;
          if (video != null) _playLocal(video);
        },
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Praxino', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _dragging ? scheme.primary : scheme.outlineVariant,
                    width: _dragging ? 2 : 1,
                  ),
                  color: _dragging
                      ? scheme.primaryContainer.withValues(alpha: 0.3)
                      : scheme.surfaceContainerLow,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.movie_outlined, size: 40, color: scheme.primary),
                    const SizedBox(height: 12),
                    const Text('把视频拖到这里，同文件夹的剧集会自动排成播放列表'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('打开文件'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _openUrl,
                          icon: const Icon(Icons.link),
                          label: const Text('打开链接'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (recent.isNotEmpty)
                Text('最近播放', style: Theme.of(context).textTheme.titleMedium),
              Expanded(
                child: ListView(
                  children: [
                    for (final file in recent)
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(p.basename(file)),
                        subtitle: Text(p.dirname(file)),
                        onTap: () => _playLocal(file),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
