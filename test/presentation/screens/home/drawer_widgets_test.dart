import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_badge.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_icon_chip.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_section_header.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_tile.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('DrawerTile', () {
    testWidgets('renders label and subtitle and reports taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          DrawerTile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            subtitle: 'Appearance',
            onTap: () => taps++,
          ),
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);

      await tester.tap(find.byType(DrawerTile));
      expect(taps, 1);
    });

    testWidgets('keeps the row at the minimum control height', (tester) async {
      await tester.pumpWidget(
        _host(const DrawerTile(icon: Icons.info_outline, label: 'About')),
      );

      final size = tester.getSize(find.byType(DrawerTile));
      expect(size.height, greaterThanOrEqualTo(DesignTokens.controlHeightMin));
    });

    testWidgets('wraps instead of truncating at a large text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 160,
            child: DrawerTile(
              icon: Icons.cloud_download_outlined,
              label: 'Downloads and offline library',
            ),
          ),
          textScaler: const TextScaler.linear(1.6),
        ),
      );

      final label = tester.widget<Text>(
        find.text('Downloads and offline library'),
      );
      expect(label.maxLines, 2);
    });
  });

  group('DrawerIconChip', () {
    testWidgets('grows with the text scale', (tester) async {
      await tester.pumpWidget(
        _host(
          const DrawerIconChip(Icons.settings_outlined),
          textScaler: const TextScaler.linear(1.3),
        ),
      );

      final chip = tester.getSize(
        find.descendant(
          of: find.byType(DrawerIconChip),
          matching: find.byType(Container),
        ),
      );
      expect(chip.width, greaterThan(DesignTokens.iconChipSize));
    });
  });

  group('DrawerSectionHeader', () {
    testWidgets('uppercases the label and shows the count badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const DrawerSectionHeader('Servers', count: 3)),
      );

      expect(find.text('SERVERS'), findsOneWidget);
      expect(find.byType(DrawerBadge), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('uses the locale mapping for dotted i', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Localizations.override(
              context: context,
              locale: const Locale('tr'),
              child: const Scaffold(body: DrawerSectionHeader('Library')),
            ),
          ),
        ),
      );

      expect(find.text('LİBRARY'), findsOneWidget);
    });
  });
}
