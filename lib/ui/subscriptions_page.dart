import 'package:flutter/material.dart';

import '../core/sources/subscription.dart';
import '../core/settings/settings_store.dart';
import 'dialog_scope.dart';

/// Manages the user's source subscriptions. The repo ships none; everything
/// here starts from an empty list and a URL the user pastes.
class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  late List<SourceSubscription> _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.settings.subscriptions);
  }

  Future<void> _persist() async {
    await widget.settings.saveSubscriptions(_items);
    if (mounted) setState(() {});
  }

  Future<void> _addFromText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => DialogScope(
        controllers: [controller],
        child: AlertDialog(
        title: const Text('粘贴规则 JSON'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '[{"name": "...", "baseURL": "..."}]',
              helperText: '支持规则数组、单个规则对象，或 {"rules": [...]}',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    ));
    if (text == null || text.trim().isEmpty || !mounted) return;

    try {
      final subscription = SourceSubscription.fromJsonText(text.trim());
      _items = [..._items, subscription];
      await _persist();
    } on SubscriptionException catch (error) {
      _toast(error.message);
    }
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => DialogScope(
        controllers: [controller],
        child: AlertDialog(
        title: const Text('添加订阅'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.test/rules.json',
            helperText: 'JSON 规则列表；仓库不内置任何源',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    ));
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final fetched =
          await SubscriptionFetcher().fetch(SourceSubscription(url: trimmed));
      if (!mounted) return;
      _items = [
        ..._items.where((item) => item.url != fetched.url),
        fetched,
      ];
      await _persist();
    } on SubscriptionException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh(SourceSubscription item) async {
    setState(() => _busy = true);
    try {
      final fetched = await SubscriptionFetcher().fetch(item);
      if (!mounted) return;
      _items = [
        for (final current in _items)
          if (current.url == fetched.url) fetched else current,
      ];
      await _persist();
    } on SubscriptionException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(SourceSubscription item, bool enabled) async {
    _items = [
      for (final current in _items)
        if (current.url == item.url) current.copyWith(enabled: enabled) else current,
    ];
    await _persist();
  }

  Future<void> _remove(SourceSubscription item) async {
    _items = _items.where((current) => current.url != item.url).toList();
    await _persist();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('源订阅'),
        actions: [
          IconButton(
            tooltip: '粘贴 JSON',
            icon: const Icon(Icons.content_paste),
            onPressed: _busy ? null : _addFromText,
          ),
          IconButton(
            tooltip: '添加订阅',
            icon: const Icon(Icons.add),
            onPressed: _busy ? null : _add,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        '还没有订阅。\n点右上角 + 添加 JSON 规则地址，或用粘贴按钮直接导入 JSON。\n'
                        '仓库不内置任何源，订阅内容由你自己提供。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final local = item.url.startsWith('local://');
                      return ListTile(
                        leading: Switch(
                          value: item.enabled,
                          onChanged: _busy
                              ? null
                              : (value) => _toggle(item, value),
                        ),
                        title: Text(item.name.isEmpty ? item.url : item.name),
                        subtitle: Text(
                          local
                              ? '本地规则 · ${item.rules.length} 条'
                              : '${item.url}\n${item.rules.length} 条规则',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: !local,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!local)
                              IconButton(
                                tooltip: '刷新',
                                icon: const Icon(Icons.refresh),
                                onPressed: _busy ? null : () => _refresh(item),
                              ),
                            IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _busy ? null : () => _remove(item),
                            ),
                          ],
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
