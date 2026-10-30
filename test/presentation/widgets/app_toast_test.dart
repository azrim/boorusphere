import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildAppToast', () {
    test('floats clear of the published bottom inset', () {
      final bar = buildAppToast(message: 'Saved', bottomInset: 80);

      expect(bar.behavior, SnackBarBehavior.floating);
      expect(
        bar.margin,
        const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          0,
          DesignTokens.spacingMd,
          80 + DesignTokens.spacingMd,
        ),
      );
    });

    test('keeps its own card background instead of the theme fill', () {
      final bar = buildAppToast(message: 'Saved');

      expect(bar.backgroundColor, Colors.transparent);
      expect(bar.elevation, 0);
      expect(bar.padding, EdgeInsets.zero);
    });
  });

  group('showToast', () {
    Widget harness({
      required void Function(BuildContext context) onShow,
      double bottomInset = 0,
    }) {
      return MaterialApp(
        home: Builder(
          builder: (context) => ToastInset(
            bottom: bottomInset,
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => onShow(context),
                  child: const Text('show'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows the message and dismisses itself', (tester) async {
      await tester.pumpWidget(
        harness(onShow: (context) => showToast(context, 'Copied to clipboard')),
      );

      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Copied to clipboard'), findsOneWidget);

      await tester.pump(DesignTokens.durationSnackbar);
      await tester.pumpAndSettle();
      expect(find.text('Copied to clipboard'), findsNothing);
    });

    testWidgets('runs the action and closes the toast', (tester) async {
      var undone = false;
      await tester.pumpWidget(
        harness(
          onShow: (context) => showToast(
            context,
            'Saved 3 posts',
            actionLabel: 'Undo',
            onAction: () => undone = true,
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(undone, isTrue);
      expect(find.text('Saved 3 posts'), findsNothing);
    });

    testWidgets('fits a long message beside an action on a narrow screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          bottomInset: 100,
          onShow: (context) => showToast(
            context,
            'The download could not be started because the server refused '
            'the request and no file was written to the device.',
            actionLabel: 'Retry',
            onAction: () {},
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  });
}
