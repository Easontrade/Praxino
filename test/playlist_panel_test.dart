import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/ui/playlist_panel.dart';

const _titles = ['第一集', '第二集', '第三集'];

Widget _panel({
  int currentIndex = 1,
  ValueChanged<int>? onSelected,
  VoidCallback? onClose,
}) =>
    MaterialApp(
      home: Scaffold(
        body: PlaylistPanel(
          titles: _titles,
          currentIndex: currentIndex,
          onSelected: onSelected ?? (_) {},
          onClose: onClose,
        ),
      ),
    );

ListTile _tile(WidgetTester tester, String title) => tester.widget<ListTile>(
      find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    );

void main() {
  testWidgets('renders every episode and marks the current one',
      (tester) async {
    await tester.pumpWidget(_panel());

    for (final title in _titles) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.byType(ListTile), findsNWidgets(_titles.length));
    // Episode numbers are 1-based.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final scheme =
        Theme.of(tester.element(find.byType(PlaylistPanel))).colorScheme;
    final tile = _tile(tester, '第二集');
    expect(tile.selected, isTrue);
    expect(tile.leading, isNotNull);
    expect(tile.selectedTileColor, scheme.primaryContainer);
    expect(tester.widget<Text>(find.text('第二集')).style?.fontWeight,
        FontWeight.bold);

    for (final other in ['第一集', '第三集']) {
      expect(_tile(tester, other).selected, isFalse);
      expect(tester.widget<Text>(find.text(other)).style?.fontWeight,
          isNot(FontWeight.bold));
    }
  });

  testWidgets('lays out as a right-side panel', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: PlaylistPanel(
            titles: _titles,
            currentIndex: 1,
            onSelected: (_) {},
            onClose: () {},
          ),
        ),
      ),
    ));

    final panel = find.byType(PlaylistPanel);
    final scheme = Theme.of(tester.element(panel)).colorScheme;
    expect(tester.getSize(panel).width, PlaylistPanel.panelWidth);
    expect(
      tester.getRect(panel).right,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
    );

    final decoration = tester
        .widget<Container>(
          find
              .descendant(of: panel, matching: find.byType(Container))
              .first,
        )
        .decoration! as BoxDecoration;
    expect(decoration.border,
        Border(left: BorderSide(color: scheme.outlineVariant)));

    final surface = tester.widget<Material>(
      find.descendant(of: panel, matching: find.byType(Material)).first,
    );
    expect(surface.color, scheme.surface);
  });

  testWidgets('tapping an episode reports its zero-based index', (tester) async {
    int? tapped;
    await tester.pumpWidget(_panel(onSelected: (index) => tapped = index));

    await tester.tap(find.text('第三集'));
    await tester.pump();

    expect(tapped, 2);
  });

  testWidgets('close button calls onClose', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_panel(onClose: () => closed++));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(closed, 1);
  });

  testWidgets('hides the close button when onClose is null', (tester) async {
    await tester.pumpWidget(_panel());

    expect(find.byIcon(Icons.close), findsNothing);
  });
}
