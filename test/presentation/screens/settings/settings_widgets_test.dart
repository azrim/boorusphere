import 'package:boorusphere/presentation/screens/settings/widgets/settings_section.dart';
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
  setUp(() {});

  group('SettingsSection', () {
    testWidgets('renders the label uppercased and exposes it as a heading', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const SettingsSection(title: 'Safe mode')));

      expect(find.text('SAFE MODE'), findsOneWidget);
      final node = tester.getSemantics(find.text('SAFE MODE'));
      expect(node.getSemanticsData().flagsCollection.isHeader, isTrue);

      handle.dispose();
    });
  });

  group('SettingsSliderTile', () {
    Widget buildTile() {
      return _host(
        SettingsSection(
          title: 'Sensitivity',
          children: [
            SettingsSliderTile(
              title: 'Swipe Down Threshold',
              value: 100,
              min: 50,
              max: 200,
              divisions: 15,
              helper: 'Distance required to trigger dismiss: 100px',
              onChanged: (_) {},
            ),
          ],
        ),
      );
    }

    testWidgets('keeps the label on one line at phone width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTile());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final labelSize = tester.getSize(find.text('Swipe Down Threshold'));
      expect(labelSize.width, greaterThan(200));
      expect(labelSize.height, lessThan(40));
    });

    testWidgets('survives a doubled text scale without overflowing', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _host(
          SettingsSection(
            title: 'Sensitivity',
            children: [
              SettingsSliderTile(
                title: 'Swipe Down Threshold',
                value: 100,
                min: 50,
                max: 200,
                divisions: 15,
                onChanged: (_) {},
              ),
            ],
          ),
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
