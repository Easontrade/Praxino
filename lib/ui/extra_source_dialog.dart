import 'package:flutter/material.dart';

import '../core/sources/extra_source.dart';

Future<ExtraSource?> showExtraSourceDialog(BuildContext context) {
  return showDialog<ExtraSource>(
    context: context,
    builder: (_) => const _ExtraSourceDialog(),
  );
}

class _ExtraSourceDialog extends StatefulWidget {
  const _ExtraSourceDialog();

  @override
  State<_ExtraSourceDialog> createState() => _ExtraSourceDialogState();
}

class _ExtraSourceDialogState extends State<_ExtraSourceDialog> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  ExtraSourceType _type = ExtraSourceType.stremio;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  void _save() {
    final location = _location.text.trim();
    if (location.isEmpty) return;
    final typeName = _type == ExtraSourceType.stremio ? 'Stremio' : '脚本';
    Navigator.pop(
      context,
      ExtraSource(
        id: '${_type.name}-${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim().isEmpty ? typeName : _name.text.trim(),
        type: _type,
        location: location,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStremio = _type == ExtraSourceType.stremio;
    return AlertDialog(
      title: const Text('添加自定义源'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ExtraSourceType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: '类型'),
              items: const [
                DropdownMenuItem(
                  value: ExtraSourceType.stremio,
                  child: Text('Stremio addon'),
                ),
                DropdownMenuItem(
                  value: ExtraSourceType.script,
                  child: Text('QuickJS 脚本源'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称（可选）'),
            ),
            TextField(
              controller: _location,
              minLines: isStremio ? 1 : 8,
              maxLines: isStremio ? 1 : 14,
              decoration: InputDecoration(
                labelText: isStremio ? 'Addon 地址' : 'JS 脚本',
                hintText: isStremio
                    ? 'https://example.test/manifest.json'
                    : 'function search(keyword) { ... }',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isStremio
                  ? '会拉取 manifest.json，并注册 catalog/meta/stream。'
                  : '脚本在 QuickJS 沙箱执行，只暴露 fetch/parseHtml/console。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('添加'),
        ),
      ],
    );
  }
}
