import 'dart:async';

import 'package:boorusphere/presentation/routes/route_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reports a route as covered while another sits above it', (
    tester,
  ) async {
    final observer = RouteObserver<Route<dynamic>>();
    final navigator = GlobalKey<NavigatorState>();
    final seen = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        home: _VisibilityProbe(observer: observer, seen: seen),
      ),
    );
    expect(seen.last, isTrue);

    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) => const Scaffold(body: Text('covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(seen.last, isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(seen.last, isTrue);
  });
}

class _VisibilityProbe extends HookWidget {
  const _VisibilityProbe({required this.observer, required this.seen});

  final RouteObserver<Route<dynamic>> observer;
  final List<bool> seen;

  @override
  Widget build(BuildContext context) {
    final visible = useRouteVisible(ModalRoute.of(context), observer);
    seen.add(visible);
    return Scaffold(body: Text('visible: $visible'));
  }
}
