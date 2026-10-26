import 'dart:io';

import 'package:flutter/material.dart';

import '../core/subtitles/assrt_provider.dart';
import '../core/subtitles/opensubtitles_provider.dart';
import '../core/subtitles/subtitle_provider.dart';
import '../core/subtitles/subtitle_store.dart';

/// Searches online subtitle providers and writes the chosen file next to the
/// video. Returns the saved path, or null when cancelled.
class SubtitleSearchDialog extends StatefulWidget {
  const SubtitleSearchDialog({
    super.key,
    required this.videoPath,
    required this.title,
    this.providers,
  });

  final String videoPath;
  final String title;
  final List<SubtitleProvider>? providers;

  @override
  State<SubtitleSearchDialog> createState() => _SubtitleSearchDialogState();
}

class _SubtitleSearchDialogState extends State<SubtitleSearchDialog> {
  late final TextEditingController _query =
      TextEditingController(text: widget.title);
  late final List<SubtitleProvider> _providers =
      widget.providers ?? _defaultProviders();
  List<SubtitleCandidate> _results = const [];
  bool _busy = false;
  String? _error;

  static List<SubtitleProvider> _defaultProviders() {
    final providers = <SubtitleProvider>[];
    final assrt = Platform.environment['PRAXINO_ASSRT_TOKEN'];
    if (assrt != null && assrt.isNotEmpty) {
      providers.add(AssrtProvider(token: assrt));
    }
    final open = Platform.environment['PRAXINO_OPENSUBTITLES_API_KEY'];
    if (open != null && open.isNotEmpty) {
      providers.add(OpenSubtitlesProvider(apiKey: open));
    }
    return providers;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_providers.isEmpty) {
      setState(() => _error = '没有配置字幕源：请设置 PRAXINO_ASSRT_TOKEN 或 '
          'PRAXINO_OPENSUBTITLES_API_KEY');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _results = const [];
    });
    final all = <SubtitleCandidate>[];
    for (final provider in _providers) {
      try {
        all.addAll(await provider.search(SubtitleQuery(title: _query.text)));
      } catch (error) {
        _error = '$error';
      }
    }
    all.sort((a, b) => b.score.compareTo(a.score));
    if (!mounted) return;
    setState(() {
      _results = all;
      _busy = false;
    });
  }

  Future<void> _choose(SubtitleCandidate candidate) async {
    SubtitleProvider? provider;
    for (final candidateProvider in _providers) {
      if (candidateProvider.id == candidate.provider) {
        provider = candidateProvider;
        break;
      }
    }
    if (provider == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await provider.download(candidate);
      final file = await SubtitleStore.save(
        videoPath: widget.videoPath,
        bytes: bytes,
        language: candidate.language,
        format: candidate.format,
      );
      if (mounted) Navigator.pop(context, file.path);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('在线搜索字幕'),
      content: SizedBox(
        width: 620,
        height: 420,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(labelText: '标题'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _search,
                  child: const Text('搜索'),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('没有结果，换个标题再试'))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        return ListTile(
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.provider} · ${item.language} · ${item.format}'
                            ' · ${item.score}',
                          ),
                          onTap: _busy ? null : () => _choose(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
