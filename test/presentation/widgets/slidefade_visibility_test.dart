import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/slidefade_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const double _chromeHeight = 60;

Widget _host({
  required bool visible,
  bool reducedMotion = false,
  HidingDirection direction = HidingDirection.toTop,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SlideFadeVisibility(
              visible: visible,
              direction: direction,
              child: const SizedBox(
                width: 200,
                height: _chromeHeight,
                child: Text('chrome'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  double opacity(WidgetTester tester) => tester
      .renderObject<RenderAnimatedOpacity>(find.byType(AnimatedOpacity))
      .opacity
      .value;

  testWidgets('chrome leaves faster than it arrives', (tester) async {
    await tester.pumpWidget(_host(visible: true));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(visible: false));
    await tester.pump();
    await tester.pump(DesignTokens.durationFast);
    expect(opacity(tester), 0.0);

    await tester.pumpWidget(_host(visible: true));
    await tester.pump();
    await tester.pump(DesignTokens.durationFast);
    // The same window is only half the arrival: a reader who dismisses the
    // chrome should not wait as long as one who called for it.
    expect(opacity(tester), greaterThan(0.0));
    expect(opacity(tester), lessThan(1.0));

    await tester.pump(DesignTokens.durationNormal);
    expect(opacity(tester), 1.0);
  });

  testWidgets('hidden chrome takes no pointers', (tester) async {
    final gate = find.descendant(
      of: find.byType(SlideFadeVisibility),
      matching: find.byType(IgnorePointer),
    );

    await tester.pumpWidget(_host(visible: true));
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(gate).ignoring, isFalse);

    await tester.pumpWidget(_host(visible: false));
    await tester.pump();
    expect(tester.widget<IgnorePointer>(gate).ignoring, isTrue);
  });

  testWidgets('reduced motion drops the travel and keeps the fade', (
    tester,
  ) async {
    await tester.pumpWidget(_host(visible: true, reducedMotion: true));
    await tester.pumpAndSettle();
    final rest = tester.getTopLeft(find.text('chrome'));

    await tester.pumpWidget(_host(visible: false, reducedMotion: true));
    await tester.pump();

    // The slide is already over on the first frame — nothing travels — while
    // the fade still has its short window left to run.
    expect(tester.getTopLeft(find.text('chrome')).dy, rest.dy - _chromeHeight);
    expect(opacity(tester), 1.0);

    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(tester), greaterThan(0.0));
    expect(opacity(tester), lessThan(1.0));

    await tester.pump(DesignTokens.durationFade);
    expect(opacity(tester), 0.0);
  });

  testWidgets('normal motion is still travelling on that first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_host(visible: true));
    await tester.pumpAndSettle();
    final rest = tester.getTopLeft(find.text('chrome'));

    await tester.pumpWidget(_host(visible: false));
    await tester.pump();
    expect(tester.getTopLeft(find.text('chrome')), rest);

    await tester.pump(const Duration(milliseconds: 60));
    final moving = tester.getTopLeft(find.text('chrome'));
    expect(moving.dy, lessThan(rest.dy));
    expect(moving.dy, greaterThan(rest.dy - _chromeHeight));
  });
}
