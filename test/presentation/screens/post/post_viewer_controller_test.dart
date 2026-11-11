import 'dart:async';

import 'package:boorusphere/presentation/screens/post/post_viewer_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bare PageView wired the way the viewer wires it: the page state follows
/// the scroll, and the host owns the controller's lifecycle.
class _ViewerHost extends StatefulWidget {
  const _ViewerHost();

  @override
  State<_ViewerHost> createState() => _ViewerHostState();
}

class _ViewerHostState extends State<_ViewerHost> {
  final controller = PostViewerController(initialPage: 0, totalPages: 3);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: controller.pageController,
      onPageChanged: controller.updateCurrentPage,
      children: const [
        ColoredBox(color: Color(0xFF000001)),
        ColoredBox(color: Color(0xFF000002)),
        ColoredBox(color: Color(0xFF000003)),
      ],
    );
  }
}

void main() {
  Widget harness(PostViewerController controller) {
    return MaterialApp(
      home: PageView(
        controller: controller.pageController,
        onPageChanged: controller.updateCurrentPage,
        children: const [
          ColoredBox(color: Color(0xFF000001)),
          ColoredBox(color: Color(0xFF000002)),
          ColoredBox(color: Color(0xFF000003)),
        ],
      ),
    );
  }

  testWidgets('a second step while one is in flight is dropped', (
    tester,
  ) async {
    final controller = PostViewerController(initialPage: 0, totalPages: 3);
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));

    unawaited(controller.nextPage(duration: const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.value.animating, isTrue);

    // Volume keys and the navigation buttons can both arrive mid-step. The
    // second request must not cancel the first: that would clear the
    // animating flag while the page is still travelling.
    unawaited(controller.nextPage(duration: const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 250));

    expect(controller.page, 1);
    expect(controller.value.animating, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a zero duration jumps instead of animating', (tester) async {
    final controller = PostViewerController(initialPage: 0, totalPages: 3);
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));

    // Reduced motion collapses the step to zero; the scroll activity a zero
    // would create asserts a positive duration, so the controller must jump.
    await controller.nextPage(duration: Duration.zero);
    await tester.pump();

    expect(controller.page, 1);
    expect(controller.value.animating, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('steps refuse to leave the page range', (tester) async {
    final controller = PostViewerController(initialPage: 0, totalPages: 3);
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));

    await controller.previousPage();
    await controller.animateToPage(0);
    await tester.pump();
    expect(controller.page, 0);
    expect(controller.value.animating, isFalse);

    await controller.animateToPage(3);
    await tester.pump();
    expect(controller.page, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tearing down mid-step does not write state after disposal', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _ViewerHost()));
    final host = tester.state<_ViewerHostState>(find.byType(_ViewerHost));

    unawaited(
      host.controller.nextPage(duration: const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Unmounting completes the in-flight animation's future, and the host
    // disposes the controller in the same pass — the continuation lands
    // after the notifier is gone, exactly like the viewer popping mid-step.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
