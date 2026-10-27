import 'dart:async';

import 'package:flutter/material.dart';

import '../core/settings/settings_store.dart';
import '../core/sources/jellyfin/jellyfin_client.dart';
import '../core/sources/source_adapter.dart';
import 'player_page.dart';

class JellyfinLibraryPage extends StatefulWidget {
  const JellyfinLibraryPage({
    super.key,
    required this.server,
    required this.settings,
    this.parentId,
    this.title,
  });

  final JellyfinServer server;
  final SettingsStore settings;
  final String? parentId;
  final String? title;

  @override
  State<JellyfinLibraryPage> createState() => _JellyfinLibraryPageState();
}

class _JellyfinLibraryPageState extends State<JellyfinLibraryPage> {
  late final JellyfinClient _client = widget.server.client();
  List<JellyfinItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = widget.parentId == null
          ? await _client.views()
          : await _client.items(widget.parentId!);
      if (mounted) setState(() => _items = items);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(JellyfinItem item) async {
    if (item.type == 'Movie' || item.type == 'Episode') {
      try {
        final playback = await _client.playback(item);
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlayerPage(
            settings: widget.settings,
            onProgress: (position) => unawaited(_client.reportProgress(
              itemId: item.id,
              position: position,
            )),
            streams: [
              PlayableStream(
                playback.url,
                headers: playback.headers,
                subtitleLanguages: [
                  for (final subtitle in playback.subtitles) subtitle.language
                ],
                subtitleUrls: {
                  for (final subtitle in playback.subtitles)
                    subtitle.language: subtitle.url,
                },
              )
            ],
          ),
        ));
      } on Exception catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('打开失败：$error')),
          );
        }
      }
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JellyfinLibraryPage(
        server: widget.server,
        settings: widget.settings,
        parentId: item.id,
        title: item.name,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? widget.server.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('媒体库为空'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          leading: Icon(item.type == 'Movie' ||
                                  item.type == 'Episode'
                              ? Icons.movie_outlined
                              : Icons.folder_outlined),
                          title: Text(item.displayName),
                          subtitle: Text(item.type),
                          onTap: () => _open(item),
                        );
                      },
                    ),
    );
  }
}
