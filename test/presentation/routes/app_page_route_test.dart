import 'package:boorusphere/presentation/routes/app_page_route.dart';
import 'package:boorusphere/presentation/routes/predictive_back_scope.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GlobalKey<NavigatorState> nav;

  setUp(() => nav = GlobalKey<NavigatorState>());

  Future<void> openSecond(WidgetTester tester) async {
    nav.currentState!.pushNamed('/second');
    await tester.pumpAndSettle();
  }

  testWidgets('a page arrives from the direction of travel', (tester) async {
    await tester.pumpWidget(_app(nav));
    await tester.pumpAndSettle();

    nav.currentState!.pushNamed('/second');
    await _onstage(tester);
    final start = tester.getTopLeft(find.text('second'));

    await tester.pump(const Duration(milliseconds: 150));
    final middle = tester.getTopLeft(find.text('second'));

    await tester.pumpAndSettle();
    final rest = tester.getTopLeft(find.text('second'));

    expect(start.dx - rest.dx, closeTo(DesignTokens.motionPageTravel, 0.01));
    expect(middle.dx, greaterThan(rest.dx));
    expect(middle.dx, lessThan(start.dx));
  });

  testWidgets('the covered page steps back and stays opaque', (tester) async {
    await tester.pumpWidget(_app(nav));
    await tester.pumpAndSettle();
    final start = tester.getTopLeft(find.text('root'));

    nav.currentState!.pushNamed('/second');
    await _onstage(tester);
    await tester.pump(const Duration(milliseconds: 150));
    final middle = tester.getTopLeft(find.text('root'));
    // An opaque page leaves the tree once the one above it has landed, so the
    // last frame of the transition is the last chance to read it.
    await tester.pump(const Duration(milliseconds: 149));
    final covered = tester.getTopLeft(find.text('root'));

    expect(middle.dx, lessThan(start.dx));
    expect(covered.dx, lessThan(middle.dx));
    expect(start.dx - covered.dx, closeTo(DesignTokens.motionPageRecede, 0.5));
    // A hole would show the window background through the page below.
    final fade = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('root'),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1.0);
  });

  testWidgets('reduced motion keeps the change of page, drops the travel', (
    tester,
  ) async {
    await tester.pumpWidget(_app(nav, reducedMotion: true));
    await tester.pumpAndSettle();
    final rootStart = tester.getTopLeft(find.text('root'));

    nav.currentState!.pushNamed('/second');
    await _onstage(tester);
    await tester.pump(const Duration(milliseconds: 150));

    final second = tester.getTopLeft(find.text('second'));
    final fade = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('second'),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, lessThan(1.0));
    expect(tester.getTopLeft(find.text('root')), rootStart);

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('second')), second);
  });

  testWidgets('a shared-subject route leaves the page below alone', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(nav, secondMotion: AppPageMotion.shared, secondOpaque: false),
    );
    await tester.pumpAndSettle();
    final rootStart = tester.getTopLeft(find.text('root'));

    await openSecond(tester);

    expect(tester.getTopLeft(find.text('root')), rootStart);
  });

  testWidgets('the back gesture drives the transition and committing pops', (
    tester,
  ) async {
    await tester.pumpWidget(_app(nav));
    await openSecond(tester);
    final rest = tester.getTopLeft(find.text('second'));

    await _backGesture(tester, 'startBackGesture', progress: 0);
    await tester.pump();
    await _backGesture(tester, 'updateBackGestureProgress', progress: 0.5);
    await tester.pump();

    // The page tracks the finger: no curve between the drag and the movement.
    final dragged = tester.getTopLeft(find.text('second'));
    expect(
      dragged.dx - rest.dx,
      closeTo(DesignTokens.motionPageTravel / 2, 0.01),
    );

    await _backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
  });

  testWidgets('a cancelled gesture returns the page to rest', (tester) async {
    await tester.pumpWidget(_app(nav));
    await openSecond(tester);
    final rest = tester.getTopLeft(find.text('second'));

    await _backGesture(tester, 'startBackGesture', progress: 0);
    await tester.pump();
    await _backGesture(tester, 'updateBackGestureProgress', progress: 0.4);
    await tester.pump();
    await _backGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('second')), rest);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('the lock cover refuses the gesture and keeps the page', (
    tester,
  ) async {
    await tester.pumpWidget(_app(nav, backAllowed: false));
    await openSecond(tester);
    final rest = tester.getTopLeft(find.text('second'));

    await _backGesture(tester, 'startBackGesture', progress: 0);
    await tester.pump();
    await _backGesture(tester, 'updateBackGestureProgress', progress: 0.5);
    await tester.pump();
    expect(tester.getTopLeft(find.text('second')), rest);

    await _backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('a page that will not pop refuses the gesture', (tester) async {
    await tester.pumpWidget(_app(nav, secondCanPop: false));
    await openSecond(tester);
    final rest = tester.getTopLeft(find.text('second'));

    await _backGesture(tester, 'startBackGesture', progress: 0);
    await tester.pump();
    await _backGesture(tester, 'updateBackGestureProgress', progress: 0.5);
    await tester.pump();
    expect(tester.getTopLeft(find.text('second')), rest);

    await _backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
  });
}

/// A pushed route is in the tree one frame before it is on stage. Both pumps
/// advance no time, so the transition is still at its first frame afterwards.
Future<void> _onstage(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Widget _app(
  GlobalKey<NavigatorState> nav, {
  bool reducedMotion = false,
  bool backAllowed = true,
  bool secondCanPop = true,
  bool secondOpaque = true,
  AppPageMotion secondMotion = AppPageMotion.forward,
}) {
  Route<dynamic> generate(RouteSettings settings) {
    final isRoot = settings.name == '/';
    return AppPageRoute<void>(
      motion: isRoot ? AppPageMotion.root : secondMotion,
      opaque: isRoot ? true : secondOpaque,
      builder: (context) {
        final page = Scaffold(
          body: Center(child: Text(isRoot ? 'root' : 'second')),
        );
        if (!isRoot && !secondCanPop) {
          return PopScope(canPop: false, child: page);
        }
        return page;
      },
    );
  }

  // The app runs on a Router, and only a Router takes a back dispatcher: the
  // gesture fallback has to be exercised through the same shape.
  return MaterialApp.router(
    routerConfig: RouterConfig<Object>(
      routerDelegate: _StackDelegate(navigatorKey: nav, generate: generate),
      backButtonDispatcher: _SwallowingDispatcher(blocked: () => !backAllowed),
    ),
    // The same slot the app shell uses: above the navigator, so the gate and
    // the platform's motion preference reach every route transition.
    builder: (context, child) => BackGate(
      allowed: backAllowed,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
    ),
  );
}

class _StackDelegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  _StackDelegate({required this.navigatorKey, required this.generate});

  @override
  final GlobalKey<NavigatorState> navigatorKey;

  final Route<dynamic> Function(RouteSettings settings) generate;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      initialRoute: '/',
      onGenerateRoute: generate,
    );
  }

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

class _SwallowingDispatcher extends RootBackButtonDispatcher {
  _SwallowingDispatcher({required this.blocked});

  final bool Function() blocked;

  @override
  Future<bool> didPopRoute() async {
    if (blocked()) return true;
    return super.didPopRoute();
  }
}

/// Sends what Android sends, so the gesture arrives on the binding the way it
/// does on a device rather than through a route method called by hand.
Future<void> _backGesture(
  WidgetTester tester,
  String method, {
  double progress = 0,
}) async {
  final arguments =
      method == 'startBackGesture' || method == 'updateBackGestureProgress'
      ? <String, Object?>{
          'touchOffset': <double>[8, 400],
          'progress': progress,
          'swipeEdge': SwipeEdge.left.index,
        }
      : null;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.backGesture.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}
