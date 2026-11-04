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
              labelFor: (value) => '${value.round()} px',
              helperFor: (value) =>
                  'Distance required to trigger dismiss: '
                  '${value.round()}px',
              onChangeEnd: (_) {},
            ),
          ],
        ),
      );
    }

    testWidgets('reads the value beside the title, above the slider', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTile());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final title = tester.getRect(find.text('Swipe Down Threshold'));
      final readout = tester.getRect(find.text('100 px'));
      final slider = tester.getRect(find.byType(Slider));
      // The number keeps the title's line and the slider keeps its own: a
      // readout that moved below the slider would make the row jump mid-drag.
      expect(readout.left, greaterThanOrEqualTo(title.right));
      expect(readout.bottom, lessThanOrEqualTo(slider.top));
    });

    testWidgets('the readout and the helper agree with the stored value', (
      tester,
    ) async {
      await tester.pumpWidget(buildTile());

      expect(find.text('100 px'), findsOneWidget);
      expect(
        find.text('Distance required to trigger dismiss: 100px'),
        findsOneWidget,
      );
    });

    testWidgets('the readout follows the finger and stores once, at the end', (
      tester,
    ) async {
      var stored = 100.0;
      Widget tile(double value) {
        return _host(
          SettingsSliderTile(
            title: 'Swipe Down Threshold',
            value: value,
            min: 50,
            max: 200,
            divisions: 15,
            labelFor: (it) => '${it.round()} px',
            onChangeEnd: (it) => stored = it,
          ),
        );
      }

      await tester.pumpWidget(tile(stored));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();

      // Mid-drag: the row shows the number under the finger, and nothing has
      // been written yet — a step per frame used to be a value per frame.
      expect(stored, 100);
      expect(find.text('100 px'), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();

      // The row stores once, at the end, and keeps showing the number it
      // stored: the draft is dropped the moment the value lands.
      expect(stored, isNot(100));
      await tester.pumpWidget(tile(stored));
      await tester.pumpAndSettle();

      expect(find.text('${stored.round()} px'), findsOneWidget);
    });

    testWidgets('a value written elsewhere replaces what the row shows', (
      tester,
    ) async {
      double stored = 100;
      Widget tile(double value) {
        return _host(
          SettingsSliderTile(
            title: 'Swipe Down Threshold',
            value: value,
            min: 50,
            max: 200,
            divisions: 15,
            labelFor: (it) => '${it.round()} px',
            onChangeEnd: (_) {},
          ),
        );
      }

      await tester.pumpWidget(tile(stored));
      expect(find.text('100 px'), findsOneWidget);

      // Another screen — or a restored archive — wrote the value. A draft the
      // row kept for itself would have gone on showing the old number.
      stored = 150;
      await tester.pumpWidget(tile(stored));
      await tester.pumpAndSettle();

      expect(find.text('150 px'), findsOneWidget);
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
                labelFor: (value) => '${value.round()} px',
                onChangeEnd: (_) {},
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
