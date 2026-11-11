import 'package:boorusphere/presentation/routes/app_page_route.dart';
import 'package:boorusphere/presentation/screens/post/hooks/surface_landed.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GlobalKey<NavigatorState> nav;
  late List<bool> log;

  setUp(() {
    nav = GlobalKey<NavigatorState>();
    log = <bool>[];
  });

  Widget app({bool enabled = true, bool asHome = false}) {
    final probe = _Probe(log, enabled: enabled);
    if (asHome) return MaterialApp(home: probe);
    return MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('root')),
    );
  }

  void open() {
    nav.currentState!.push(
      AppPageRoute<void>(
        motion: AppPageMotion.shared,
        opaque: false,
        builder: (context) => _Probe(log),
      ),
    );
  }

  testWidgets('the frame a route is installed on is not a landing', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    open();
    // The route's animation is a parentless proxy here and reads 1.0. Chrome
    // that believed it would flash in and out before the artwork had left.
    await tester.pump();
    expect(log.last, isFalse);

    await tester.pump(const Duration(milliseconds: 100));
    expect(log.last, isFalse);

    await tester.pump(const Duration(milliseconds: 100));
    expect(log.last, isTrue);
  });

  testWidgets('the gate hands back while the surface is returning', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    open();
    await tester.pumpAndSettle();
    expect(log.last, isTrue);

    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(log.last, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    expect(log.last, isFalse);
  });

  testWidgets('a route added without a transition has already landed', (
    tester,
  ) async {
    await tester.pumpWidget(app(asHome: true));
    await tester.pump();
    await tester.pump();
    expect(log.last, isTrue);
  });

  testWidgets('no arrival to hand over from opens the gate at once', (
    tester,
  ) async {
    await tester.pumpWidget(app(asHome: true, enabled: false));
    await tester.pump();
    expect(log.last, isTrue);
  });

  testWidgets('the handover is the share the fade already claims', (
    tester,
  ) async {
    // The surface is solid at the same moment the chrome is allowed in, so
    // the controls never arrive over a page still showing through.
    expect(DesignTokens.durationNormal.inMilliseconds, 300);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 179));
    expect(log.last, isFalse);
    await tester.pump(const Duration(milliseconds: 2));
    expect(log.last, isTrue);
  });
}

class _Probe extends HookWidget {
  const _Probe(this.log, {this.enabled = true});

  final List<bool> log;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final landed = useSurfaceLanded(
      ModalRoute.of(context)?.animation,
      handover: 0.6,
      enabled: enabled,
    );
    log.add(landed);
    return const ColoredBox(color: Color(0xFF000000));
  }
}
