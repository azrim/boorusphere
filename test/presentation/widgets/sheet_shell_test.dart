import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _panelHeight = 240;

Widget _host({bool reducedMotion = false}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(
                    height: _panelHeight,
                    child: Text('panel'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  /// Opens the sheet and returns the panel's top edge on its first onstage
  /// frame, before any transition time has been given.
  Future<double> openAndMeasure(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    // A pushed route is in the tree one frame before it is onstage.
    await tester.pump();
    return tester.getTopLeft(find.text('panel')).dy;
  }

  testWidgets('a sheet arrives from the edge it is pinned to', (tester) async {
    await tester.pumpWidget(_host());
    final early = await openAndMeasure(tester);

    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(find.text('panel')).dy;

    expect(early, greaterThan(settled));
    expect(settled, closeTo(600 - _panelHeight, 0.01));
  });

  testWidgets('reduced motion puts the sheet in place at once', (tester) async {
    await tester.pumpWidget(_host(reducedMotion: true));
    final early = await openAndMeasure(tester);

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('panel')).dy, early);
  });

  testWidgets('the sheet leaves faster than it came', (tester) async {
    await tester.pumpWidget(_host());
    await openAndMeasure(tester);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('panel')).dy,
      closeTo(600 - _panelHeight, 0.01),
    );

    Navigator.of(tester.element(find.text('panel'))).pop();
    await tester.pump();
    await tester.pump(DesignTokens.durationFast);

    // The whole height is already travelled in the short window — the same
    // window that only half-finished the arrival.
    expect(tester.getTopLeft(find.text('panel')).dy, closeTo(600, 0.01));
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsNothing);
  });
}
