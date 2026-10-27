import 'package:flutter/material.dart';

import '../core/settings/settings_store.dart';
import '../core/sources/webdav/webdav_adapter.dart';
import '../core/sources/webdav/webdav_client.dart';
import '../core/sources/webdav/webdav_server.dart';
import 'player_page.dart';

class WebDavBrowserPage extends StatefulWidget {
  const WebDavBrowserPage({
    super.key,
    required this.server,
    required this.settings,
    this.initialPath = '/',
  });

  final WebDavServer server;
  final SettingsStore settings;
  final String initialPath;

  @override
  State<WebDavBrowserPage> createState() => _WebDavBrowserPageState();
}

class _WebDavBrowserPageState extends State<WebDavBrowserPage> {
  late final WebDavClient _client = widget.server.client();
  String _path = '/';
  List<WebDavEntry> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(widget.initialPath);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _load(String path) async {
    setState(() {
      _path = path;
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _client.list(path);
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (mounted) setState(() => _entries = entries);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(WebDavEntry entry) async {
    if (entry.isDirectory) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebDavBrowserPage(
          server: widget.server,
          settings: widget.settings,
          initialPath: entry.path,
        ),
      ));
      return;
    }
    final videos = _entries
        .where((item) => !item.isDirectory && WebDavAdapter.isVideoName(item.name))
        .toList();
    final index = videos.indexWhere((item) => item.path == entry.path);
    if (index < 0) return;
    final headers = _client.headers['Authorization'];
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        settings: widget.settings,
        sources: [
          for (final video in videos) _client.uriFor(video.path).toString()
        ],
        index: index,
        headers: headers == null ? const {} : {'Authorization': headers},
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.server.name} · $_path'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(_path),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _entries.isEmpty
                  ? const Center(child: Text('空目录'))
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        return ListTile(
                          leading: Icon(entry.isDirectory
                              ? Icons.folder_outlined
                              : Icons.movie_outlined),
                          title: Text(entry.name),
                          subtitle: entry.length == null
                              ? null
                              : Text('${(entry.length! / 1024 / 1024).toStringAsFixed(1)} MB'),
                          onTap: () => _open(entry),
                        );
                      },
                    ),
    );
  }
}
