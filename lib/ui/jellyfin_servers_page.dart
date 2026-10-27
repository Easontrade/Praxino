import 'package:flutter/material.dart';

import '../core/settings/settings_store.dart';
import '../core/sources/jellyfin/jellyfin_client.dart';
import 'dialog_scope.dart';
import 'jellyfin_library_page.dart';

class JellyfinServersPage extends StatefulWidget {
  const JellyfinServersPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<JellyfinServersPage> createState() => _JellyfinServersPageState();
}

class _JellyfinServersPageState extends State<JellyfinServersPage> {
  late List<JellyfinServer> _items = List.of(widget.settings.jellyfinServers);

  Future<void> _save() => widget.settings.saveJellyfinServers(_items);

  Future<void> _add() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final user = TextEditingController();
    final pass = TextEditingController();
    var isEmby = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => DialogScope(
          controllers: [name, url, user, pass],
          child: AlertDialog(
          title: const Text('添加 Jellyfin / Emby'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://example.test:8096',
                  ),
                ),
                TextField(
                  controller: user,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('这是 Emby 服务器'),
                  value: isEmby,
                  onChanged: (value) =>
                      setDialogState(() => isEmby = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('登录'),
            ),
          ],
        ),
        ),
      ),
    );
    if (ok == true && url.text.trim().isNotEmpty) {
      try {
        final client = await JellyfinClient.login(
          baseUrl: url.text.trim(),
          username: user.text.trim(),
          password: pass.text,
          isEmby: isEmby,
        );
        final server = JellyfinServer(
          name: name.text.trim().isEmpty ? 'Jellyfin' : name.text.trim(),
          baseUrl: url.text.trim(),
          userId: client.userId,
          token: client.token,
          deviceId: client.deviceId,
          isEmby: isEmby,
        );
        setState(() => _items = [..._items, server]);
        await _save();
        client.close();
        if (mounted) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => JellyfinLibraryPage(
              server: server,
              settings: widget.settings,
            ),
          ));
        }
      } on Exception catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('登录失败：$error')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jellyfin / Emby')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: '添加服务器',
        child: const Icon(Icons.add),
      ),
      body: _items.isEmpty
          ? const Center(child: Text('还没有媒体服务器'))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final server = _items[index];
                return ListTile(
                  leading: const Icon(Icons.video_library_outlined),
                  title: Text(server.name),
                  subtitle: Text(server.baseUrl),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => JellyfinLibraryPage(
                      server: server,
                      settings: widget.settings,
                    ),
                  )),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      setState(() => _items =
                          _items.where((item) => item != server).toList());
                      await _save();
                    },
                  ),
                );
              },
            ),
    );
  }
}
