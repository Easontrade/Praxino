import 'package:flutter/material.dart';

/// One selectable track, decoupled from media_kit's track classes so the
/// menu can be widget-tested without a player.
class TrackOption {
  const TrackOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Player-bar button for audio, subtitle and secondary-subtitle selection.
///
/// Like the enhancement options this opens a dialog rather than a MenuAnchor:
/// the control bar hides when the pointer leaves the video, which used to
/// unmount an anchored menu before the user could click it.
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
    return IconButton(
      tooltip: '音轨 / 字幕',
      icon: const Icon(Icons.audiotrack_outlined),
      onPressed: empty ? null : () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => _TrackDialog(
          audio: audio,
          subtitles: subtitles,
          selectedAudio: selectedAudio,
          selectedSubtitle: selectedSubtitle,
          selectedSecondary: selectedSecondary,
          onAudio: onAudio,
          onSubtitle: onSubtitle,
          onSecondary: onSecondary,
        ),
      );
}

class _TrackDialog extends StatefulWidget {
  const _TrackDialog({
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
  State<_TrackDialog> createState() => _TrackDialogState();
}

class _TrackDialogState extends State<_TrackDialog> {
  late String? _audio = widget.selectedAudio;
  late String? _subtitle = widget.selectedSubtitle;
  late String? _secondary = widget.selectedSecondary;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('音轨 / 字幕'),
      content: SizedBox(
        width: 380,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.audio.isNotEmpty) ...[
                  const _Header('音轨'),
                  for (final track in widget.audio)
                    _Choice(
                      label: track.label,
                      selected: track.id == _audio,
                      onTap: () {
                        setState(() => _audio = track.id);
                        widget.onAudio(track.id);
                      },
                    ),
                ],
                if (widget.subtitles.isNotEmpty) ...[
                  if (widget.audio.isNotEmpty) const Divider(),
                  const _Header('字幕'),
                  _Choice(
                    label: '关闭字幕',
                    selected: _subtitle == null,
                    onTap: () {
                      setState(() => _subtitle = null);
                      widget.onSubtitle(null);
                    },
                  ),
                  for (final track in widget.subtitles)
                    _Choice(
                      label: track.label,
                      selected: track.id == _subtitle,
                      onTap: () {
                        setState(() => _subtitle = track.id);
                        widget.onSubtitle(track.id);
                      },
                    ),
                  const Divider(),
                  const _Header('第二字幕'),
                  _Choice(
                    label: '关闭',
                    selected: _secondary == null,
                    onTap: () {
                      setState(() => _secondary = null);
                      widget.onSecondary(null);
                    },
                  ),
                  for (final track in widget.subtitles)
                    _Choice(
                      label: track.label,
                      selected: track.id == _secondary,
                      onTap: () {
                        setState(() => _secondary = track.id);
                        widget.onSecondary(track.id);
                      },
                    ),
                ],
              ],
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
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 20,
        ),
        title: Text(label),
        onTap: onTap,
      );
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
