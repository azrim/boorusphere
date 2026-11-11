import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/timeline/post_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _groups = [
  [
    PostContextMenuEntry(
      action: PostContextMenuAction.select,
      icon: Icons.check,
      label: 'Select',
    ),
    PostContextMenuEntry(
      action: PostContextMenuAction.favorite,
      icon: Icons.favorite,
      label: 'Favorite',
    ),
  ],
  [
    PostContextMenuEntry(
      action: PostContextMenuAction.download,
      icon: Icons.download,
      label: 'Download',
    ),
    PostContextMenuEntry(
      action: PostContextMenuAction.share,
      icon: Icons.share,
      label: 'Share',
    ),
  ],
];

Widget _host({bool reducedMotion = false}) {
  return MaterialApp(
    // Above the Navigator: the menu is a route of its own, so a MediaQuery
    // placed inside `home` would never reach the rows it builds.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
      child: child!,
    ),
    home: Center(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => showPostContextMenu(context, groups: _groups),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    // A pushed route is in the tree one frame before it is onstage.
    await tester.pump();
  }

  /// The opacity painted over a row, which is what the stagger controls.
  double rowOpacity(WidgetTester tester, String label) {
    final opacity = find.ancestor(
      of: find.text(label),
      matching: find.byType(Opacity),
    );
    return tester.widget<Opacity>(opacity.first).opacity;
  }

  testWidgets('rows arrive one after another', (tester) async {
    await tester.pumpWidget(_host());
    await open(tester);
    await tester.pump(const Duration(milliseconds: 90));

    expect(rowOpacity(tester, 'Select'), greaterThan(0.0));
    expect(rowOpacity(tester, 'Share'), 0.0);

    await tester.pumpAndSettle();
    expect(rowOpacity(tester, 'Share'), 1.0);
  });

  testWidgets('an invisible row is not a control', (tester) async {
    await tester.pumpWidget(_host());
    await open(tester);
    await tester.pump(const Duration(milliseconds: 90));

    final gate = find
        .ancestor(of: find.text('Share'), matching: find.byType(IgnorePointer))
        .first;
    expect(tester.widget<IgnorePointer>(gate).ignoring, isTrue);

    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(gate).ignoring, isFalse);
  });

  testWidgets('reduced motion brings the whole menu in one fade', (
    tester,
  ) async {
    await tester.pumpWidget(_host(reducedMotion: true));
    await open(tester);

    // No stagger and no travel: every row is already in place, and the card
    // itself is not offset from where it will rest.
    expect(rowOpacity(tester, 'Select'), 1.0);
    expect(rowOpacity(tester, 'Share'), 1.0);
    final rest = tester.getTopLeft(find.text('Select'));

    // The route still fades, over the short window rather than not at all.
    double routeFade() => tester
        .renderObject<RenderAnimatedOpacity>(
          find
              .ancestor(
                of: find.text('Select'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(routeFade(), lessThan(1.0));

    await tester.pump(DesignTokens.durationFade);
    expect(routeFade(), 1.0);
    expect(tester.getTopLeft(find.text('Select')), rest);
  });
}
