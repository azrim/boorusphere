import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_tile.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/in_block_note.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:boorusphere/presentation/widgets/sectioned_list.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('InBlockNote', () {
    testWidgets('starts where the row beside it starts', (tester) async {
      await tester.pumpWidget(
        _host(
          const TileGroup(
            children: [
              ListTile(title: Text('Back up automatically')),
              InBlockNote(text: 'Turn on periodic backups to set this'),
            ],
          ),
        ),
      );

      // The note is not a row, so nothing forces it onto the row's inset; a page
      // that pads it by hand is how the two edges came to differ.
      expect(
        tester.getRect(find.text('Turn on periodic backups to set this')).left,
        tester.getRect(find.text('Back up automatically')).left,
      );
    });
  });

  group('Row scale', () {
    testWidgets('a drawer row is the same row as a grouped row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              TileGroup(
                children: [
                  ListTile(
                    leading: Icon(Icons.settings),
                    title: Text('Grouped row'),
                  ),
                ],
              ),
              SectionSurface(
                children: [
                  DrawerTile(icon: Icons.settings, label: 'Drawer row'),
                ],
              ),
            ],
          ),
        ),
      );

      // Two row systems, one scale: the block owns the border and the 4 dp it
      // gives its children, so both rows start their leading glyph at the same
      // edge, keep the same gap to the label, and set that label in the same
      // role. The rows themselves differ only in the icon each of them draws.
      final groupedIcon = tester.getRect(find.byIcon(Icons.settings).first);
      final drawerIcon = tester.getRect(find.byIcon(Icons.settings).last);
      final groupedLabel = tester.getRect(find.text('Grouped row'));
      final drawerLabel = tester.getRect(find.text('Drawer row'));

      expect(drawerIcon.left, groupedIcon.left);
      expect(
        drawerLabel.left - drawerIcon.right,
        groupedLabel.left - groupedIcon.right,
      );
      expect(drawerLabel.height, groupedLabel.height);
    });
  });

  group('SectionedList', () {
    testWidgets('keeps one gutter and no top inset', (tester) async {
      const block = Key('block');
      await tester.pumpWidget(
        _host(
          const SectionedList(
            children: [SizedBox(key: block, height: 100, width: 100)],
          ),
        ),
      );

      final list = tester.getRect(find.byType(SectionedList));
      final first = tester.getRect(find.byKey(block));

      expect(first.left - list.left, DesignTokens.spacingMd);
      // The first child starts at the very top of the list: the gap above a
      // block belongs to its heading, and the list must not double it.
      expect(first.top, list.top);
      expect(
        tester.widget<ListView>(find.byType(ListView)).padding,
        const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          0,
          DesignTokens.spacingMd,
          DesignTokens.spacingLg,
        ),
      );
    });
  });
}
