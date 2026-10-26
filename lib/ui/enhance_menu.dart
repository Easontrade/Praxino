import 'package:flutter/material.dart';

import '../core/enhance/enhance_settings.dart';

/// Player-bar button that opens the picture-enhancement menu.
class EnhanceButton extends StatelessWidget {
  const EnhanceButton({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ValueNotifier<EnhanceSettings> settings;
  final ValueChanged<EnhanceSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: settings,
      builder: (context, value, _) => MenuAnchor(
        style: const MenuStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
        ),
        menuChildren: [
          const _Header('超分辨率'),
          for (final preset in UpscalePreset.values)
            MenuItemButton(
              leadingIcon: Icon(
                preset == value.upscale
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
              ),
              onPressed: () => onChanged(value.copyWith(upscale: preset)),
              child: _Item(preset.label, preset.hint),
            ),
          const Divider(height: 12),
          const _Header('画质修复'),
          CheckboxMenuButton(
            value: value.deband,
            closeOnActivate: false,
            onChanged: (v) => onChanged(value.copyWith(deband: v)),
            child: const _Item('去色带', '平坦区域的条状色阶'),
          ),
          CheckboxMenuButton(
            value: value.denoise,
            closeOnActivate: false,
            onChanged: (v) => onChanged(value.copyWith(denoise: v)),
            child: const _Item('轻度降噪', '低码率片源的蚊式噪声和块效应'),
          ),
        ],
        builder: (context, menu, _) => IconButton(
          tooltip: '画质增强 (Ctrl+0~3)',
          icon: Icon(
            value.isOff ? Icons.auto_awesome_outlined : Icons.auto_awesome,
            color: value.isOff ? Colors.white : Colors.amberAccent,
          ),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      );
}

class _Item extends StatelessWidget {
  const _Item(this.title, this.hint);

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
