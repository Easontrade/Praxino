import 'package:flutter/material.dart';

import '../core/enhance/enhance_settings.dart';
import '../core/enhance/interpolation.dart';

/// Player-bar button that opens the picture-enhancement dialog.
///
/// This used to be a [MenuAnchor] inside the auto-hiding control bar. Moving
/// the mouse onto the menu left the video's hover region, so the controls hid,
/// unmounted the anchor and the whole menu vanished. A dialog is independent of
/// the control bar and stays open while the user picks options.
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
      builder: (context, value, _) => IconButton(
        tooltip: '画质增强 (Ctrl+0~3)',
        icon: Icon(
          value.isOff ? Icons.auto_awesome_outlined : Icons.auto_awesome,
          color: value.isOff ? Colors.white : Colors.amberAccent,
        ),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) =>
              _EnhanceDialog(settings: settings, onChanged: onChanged),
        ),
      ),
    );
  }
}

class _EnhanceDialog extends StatelessWidget {
  const _EnhanceDialog({required this.settings, required this.onChanged});

  final ValueNotifier<EnhanceSettings> settings;
  final ValueChanged<EnhanceSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('画质增强'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ValueListenableBuilder(
            valueListenable: settings,
            builder: (context, value, _) => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header('超分辨率'),
                  _Choice(
                    selected: value.upscale == UpscalePreset.off,
                    title: UpscalePreset.off.label,
                    hint: UpscalePreset.off.hint,
                    onTap: () =>
                        onChanged(value.copyWith(upscale: UpscalePreset.off)),
                  ),
                  const _Header('动画'),
                  for (final preset in const [
                    UpscalePreset.anime4kFast,
                    UpscalePreset.anime4kBalanced,
                    UpscalePreset.anime4kQuality,
                  ])
                    _Choice(
                      selected: value.upscale == preset,
                      title: preset.label,
                      hint: preset.hint,
                      onTap: () =>
                          onChanged(value.copyWith(upscale: preset)),
                    ),
                  const _Header('实拍'),
                  _Choice(
                    selected: value.upscale == UpscalePreset.fsrcnnx,
                    title: UpscalePreset.fsrcnnx.label,
                    hint: UpscalePreset.fsrcnnx.hint,
                    onTap: () =>
                        onChanged(value.copyWith(upscale: UpscalePreset.fsrcnnx)),
                  ),
                  const Divider(),
                  const _Header('画质修复'),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: value.deband,
                    onChanged: (checked) =>
                        onChanged(value.copyWith(deband: checked)),
                    title: const Text('去色带'),
                    subtitle: const Text('平坦区域的条状色阶'),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: value.denoise,
                    onChanged: (checked) =>
                        onChanged(value.copyWith(denoise: checked)),
                    title: const Text('轻度降噪'),
                    subtitle: const Text('低码率片源的蚊式噪声和块效应'),
                  ),
                  const Divider(),
                  const _Header('补帧'),
                  for (final mode in InterpolationMode.values)
                    _Choice(
                      selected: value.interpolation == mode,
                      title: switch (mode) {
                        InterpolationMode.off => '关闭',
                        InterpolationMode.smooth => '平滑（内置）',
                        InterpolationMode.mvtools => 'mvtools',
                        InterpolationMode.rife => 'RIFE',
                      },
                      hint: switch (mode) {
                        InterpolationMode.off => '原始帧率',
                        InterpolationMode.smooth => 'mpv 内置，无 AI、音画稳定、跳转快',
                        InterpolationMode.mvtools => '运动补偿，CPU，轻量',
                        InterpolationMode.rife => 'AI 补帧，GPU（Vulkan），效果更好',
                      },
                      onTap: () => onChanged(
                        value.copyWith(interpolation: mode),
                      ),
                    ),
                  const _Header('RIFE 档位'),
                  for (final profile in RifeProfile.values)
                    _Choice(
                      selected: value.rifeProfile == profile,
                      title: profile.label,
                      hint: profile.hint,
                      onTap: () => onChanged(
                        value.copyWith(rifeProfile: profile),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 20,
      ),
      title: Text(title),
      subtitle: Text(hint, style: Theme.of(context).textTheme.bodySmall),
      onTap: onTap,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      );
}
