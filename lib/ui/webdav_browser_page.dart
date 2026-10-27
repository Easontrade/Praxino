import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/settings/settings_store.dart';
import '../core/sources/source_adapter.dart';
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
    final base = p.basenameWithoutExtension(entry.name);
    final subtitles = <String, String>{};
    for (final item in _entries) {
      if (item.isDirectory) continue;
      final ext = p.extension(item.name).toLowerCase();
      if (ext != '.srt' && ext != '.ass' && ext != '.vtt') continue;
      if (p.basenameWithoutExtension(item.name) != base) continue;
      subtitles[item.name] = _client.uriFor(item.path).toString();
    }
    final headers = _client.headers['Authorization'];
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        settings: widget.settings,
        streams: [
          PlayableStream(
            _client.uriFor(entry.path).toString(),
            headers: headers == null ? const {} : {'Authorization': headers},
            subtitleLanguages: subtitles.keys.toList(),
            subtitleUrls: subtitles,
          )
        ],
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
