import 'package:flutter/material.dart';

import '../core/settings/settings_store.dart';
import '../core/sources/webdav/webdav_server.dart';
import 'dialog_scope.dart';
import 'webdav_browser_page.dart';

class WebDavServersPage extends StatefulWidget {
  const WebDavServersPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<WebDavServersPage> createState() => _WebDavServersPageState();
}

class _WebDavServersPageState extends State<WebDavServersPage> {
  late List<WebDavServer> _items = List.of(widget.settings.webdavServers);

  Future<void> _save() => widget.settings.saveWebDavServers(_items);

  Future<void> _add() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final user = TextEditingController();
    final pass = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => DialogScope(
        controllers: [name, url, user, pass],
        child: AlertDialog(
        title: const Text('添加 WebDAV / OpenList'),
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
                  labelText: '地址',
                  hintText: 'https://example.test/dav',
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
            child: const Text('保存'),
          ),
        ],
      ),
    ));
    if (saved == true && url.text.trim().isNotEmpty) {
      setState(() {
        _items = [
          ..._items,
          WebDavServer(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name.text.trim().isEmpty ? 'WebDAV' : name.text.trim(),
            baseUrl: url.text.trim(),
            username: user.text.trim(),
            password: pass.text,
          ),
        ];
      });
      await _save();
    }
  }

  Future<void> _delete(WebDavServer server) async {
    setState(() => _items = _items.where((item) => item.id != server.id).toList());
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV / OpenList')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: '添加服务器',
        child: const Icon(Icons.add),
      ),
      body: _items.isEmpty
          ? const Center(child: Text('还没有 WebDAV 服务器'))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final server = _items[index];
                return ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(server.name),
                  subtitle: Text(server.baseUrl),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => WebDavBrowserPage(
                      server: server,
                      settings: widget.settings,
                    ),
                  )),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(server),
                  ),
                );
              },
            ),
    );
  }
}
