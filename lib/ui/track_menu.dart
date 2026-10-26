import 'package:flutter/material.dart';

/// One selectable track, decoupled from media_kit's track classes so the
/// menu can be widget-tested without a player.
class TrackOption {
  const TrackOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Player-bar button for audio, subtitle and secondary-subtitle selection.
class TrackMenu extends StatelessWidget {
  const TrackMenu({
    super.key,
    required this.audio,
    required this.subtitles,
    required this.selectedAudio,
    required this.selectedSubtitle,
    required this.selectedSecondary,
    required this.onAudio,
    required this.onSubtitle,
    required this.onSecondary,
  });

  final List<TrackOption> audio;
  final List<TrackOption> subtitles;
  final String? selectedAudio;
  final String? selectedSubtitle;
  final String? selectedSecondary;
  final ValueChanged<String> onAudio;
  final ValueChanged<String?> onSubtitle;
  final ValueChanged<String?> onSecondary;

  @override
  Widget build(BuildContext context) {
    final empty = audio.isEmpty && subtitles.isEmpty;
    return MenuAnchor(
      menuChildren: [
        if (audio.isNotEmpty) ...[
          const _Header('音轨'),
          for (final track in audio)
            _choice(
              track.label,
              track.id == selectedAudio,
              () => onAudio(track.id),
            ),
        ],
        if (subtitles.isNotEmpty) ...[
          if (audio.isNotEmpty) const Divider(height: 12),
          const _Header('字幕'),
          _choice(
            '关闭字幕',
            selectedSubtitle == null,
            () => onSubtitle(null),
          ),
          for (final track in subtitles)
            _choice(
              track.label,
              track.id == selectedSubtitle,
              () => onSubtitle(track.id),
            ),
          const Divider(height: 12),
          const _Header('第二字幕'),
          _choice('关闭', selectedSecondary == null, () => onSecondary(null)),
          for (final track in subtitles)
            _choice(
              track.label,
              track.id == selectedSecondary,
              () => onSecondary(track.id),
            ),
        ],
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: '音轨 / 字幕',
        icon: const Icon(Icons.audiotrack_outlined),
        onPressed: empty
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onPressed) {
    return MenuItemButton(
      leadingIcon: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 18,
      ),
      onPressed: onPressed,
      child: Text(label),
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
