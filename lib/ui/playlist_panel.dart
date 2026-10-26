import 'package:flutter/material.dart';

/// Right-side panel listing the episodes of the current playlist.
///
/// The player page owns the open/closed state; this widget only renders
/// [titles] and reports taps through [onSelected].
class PlaylistPanel extends StatelessWidget {
  const PlaylistPanel({
    super.key,
    required this.titles,
    required this.currentIndex,
    required this.onSelected,
    this.onClose,
  });

  /// Episode titles, in playlist order.
  final List<String> titles;

  /// Index of the episode being played.
  final int currentIndex;

  /// Called with the zero-based index of the tapped episode.
  final ValueChanged<int> onSelected;

  /// Closes the panel; the close button is hidden when null.
  final VoidCallback? onClose;

  /// Fixed width so the video keeps the rest of the window.
  static const double panelWidth = 300;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: Material(
        color: colors.surface,
        child: Column(
          children: [
            // Header: panel title plus an optional close button.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('选集', style: theme.textTheme.titleMedium),
                  ),
                  if (onClose != null)
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: titles.length,
                itemBuilder: (context, index) {
                  final selected = index == currentIndex;
                  return ListTile(
                    leading: SizedBox(
                      width: 28,
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.end,
                      ),
                    ),
                    title: Text(
                      titles[index],
                      overflow: TextOverflow.ellipsis,
                      style: selected
                          ? const TextStyle(fontWeight: FontWeight.bold)
                          : null,
                    ),
                    selected: selected,
                    selectedTileColor: colors.primaryContainer,
                    onTap: () => onSelected(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
