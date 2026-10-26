import 'package:flutter/material.dart';

import '../core/settings/settings_store.dart';
import '../core/sources/extra_source.dart';
import 'extra_source_dialog.dart';

/// Manage user-added Stremio addons and QuickJS script sources.
class ExtraSourcesPage extends StatefulWidget {
  const ExtraSourcesPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<ExtraSourcesPage> createState() => _ExtraSourcesPageState();
}

class _ExtraSourcesPageState extends State<ExtraSourcesPage> {
  late List<ExtraSource> _items = List.of(widget.settings.extraSources);

  Future<void> _save() => widget.settings.saveExtraSources(_items);

  Future<void> _add() async {
    final source = await showExtraSourceDialog(context);
    if (source == null) return;
    setState(() => _items = [..._items, source]);
    await _save();
  }

  Future<void> _toggle(ExtraSource source, bool enabled) async {
    setState(() {
      _items = [
        for (final item in _items)
          item.id == source.id ? item.copyWith(enabled: enabled) : item,
      ];
    });
    await _save();
  }

  Future<void> _delete(ExtraSource source) async {
    setState(() => _items = _items.where((item) => item.id != source.id).toList());
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扩展源')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: '添加扩展源',
        child: const Icon(Icons.add),
      ),
      body: _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '还没有扩展源。\n可以添加 Stremio addon 或 QuickJS 脚本源。',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  leading: Switch(
                    value: item.enabled,
                    onChanged: (value) => _toggle(item, value),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.type == ExtraSourceType.stremio ? 'Stremio' : '脚本'}'
                    ' · ${item.location.split(RegExp(r'[\r\n]')).first}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(item),
                  ),
                );
              },
            ),
    );
  }
}
