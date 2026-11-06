import 'package:boorusphere/presentation/widgets/pin_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('PinKeypad submit key', () {
    testWidgets('the blank cell stays blank without a submit handler', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(PinKeypad(onDigit: (_) {}, onBackspace: () {})),
      );

      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
    });

    testWidgets('a wired submit key answers once the entry is long enough', (
      tester,
    ) async {
      var submitted = 0;
      var digits = '';

      await tester.pumpWidget(
        _host(
          PinKeypad(
            onDigit: (digit) => digits += digit,
            onBackspace: () {},
            onSubmit: () => submitted++,
            submitEnabled: digits.length >= 4,
          ),
        ),
      );

      // Too short: the key is present but does not answer.
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(submitted, 0);

      // Rebuild the way the gate does after each digit, then confirm.
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
        await tester.pumpWidget(
          _host(
            PinKeypad(
              onDigit: (d) => digits += d,
              onBackspace: () {},
              onSubmit: () => submitted++,
              submitEnabled: digits.length >= 4,
            ),
          ),
        );
      }
      expect(digits, '1234');

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(submitted, 1);
    });

    testWidgets('the submit key is named for a reader', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          PinKeypad(
            onDigit: (_) {},
            onBackspace: () {},
            onSubmit: () {},
            submitEnabled: true,
          ),
        ),
      );

      expect(find.bySemanticsLabel('Continue'), findsOneWidget);
      handle.dispose();
    });
  });
}
