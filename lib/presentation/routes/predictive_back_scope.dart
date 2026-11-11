import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'package:flutter/widgets.dart';

/// Whether Android back may reach the navigator right now.
///
/// The lock cover is a sibling of the app content in the shell, not a route, so
/// it has no [PopScope] to register and no route of its own to be current. The
/// shell publishes the answer here and [PredictiveBackScope] reads it before
/// accepting a gesture.
class BackGate extends InheritedWidget {
  const BackGate({super.key, required this.allowed, required super.child});

  final bool allowed;

  /// Read at the moment the gesture arrives, not at build time: the cover can
  /// come up between two frames, and a value captured earlier would answer for
  /// a screen the user can no longer see.
  static bool allows(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BackGate>()?.allowed ?? true;

  @override
  bool updateShouldNotify(BackGate oldWidget) => oldWidget.allowed != allowed;
}

/// Lets the Android back gesture drive this route's own transition.
///
/// Without it the platform animates a preview of the previous activity and the
/// app only finds out at the end, so the page the user is dragging towards is
/// not the page the app draws. The gesture events arrive on
/// [WidgetsBindingObserver] rather than through [BackButtonDispatcher], which
/// is why the lock has to be consulted here as well: a gesture accepted under
/// the cover would pop pages the user cannot see.
///
/// Refusing the gesture is not the same as swallowing back. When no observer
/// accepts it, the platform falls back to the ordinary pop dispatch, which the
/// shell's dispatcher and the page's own [PopScope] already answer.
class PredictiveBackScope extends StatefulWidget {
  const PredictiveBackScope({
    super.key,
    required this.route,
    required this.builder,
  });

  final PageRoute<dynamic> route;

  /// Builds the transition. A builder rather than a child: the transition reads
  /// [PageRoute.popGestureInProgress], and the framework only rebuilds it when
  /// an animation ticks. The flag can flip with the animation already at rest
  /// (a gesture released at full progress), so the scope rebuilds it itself.
  final WidgetBuilder builder;

  @override
  State<PredictiveBackScope> createState() => _PredictiveBackScopeState();
}

class _PredictiveBackScopeState extends State<PredictiveBackScope>
    with WidgetsBindingObserver {
  /// Whether this scope accepted the gesture currently in flight. The binding
  /// only sends the later events to observers that accepted the start, but a
  /// route can stop being current mid-gesture, and the field keeps the rest of
  /// the sequence from driving a transition that is no longer ours.
  bool _tracking = false;

  bool get _canStart =>
      widget.route.isCurrent &&
      widget.route.popGestureEnabled &&
      BackGate.allows(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // A button press is not a drag: it has no progress to follow, and the
    // ordinary dispatch already handles it.
    if (backEvent.isButtonEvent || !_canStart) return false;

    // The platform counts progress towards leaving; the route counts towards
    // being shown.
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    setState(() => _tracking = true);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_tracking) return;
    widget.route.handleUpdateBackGestureProgress(
      progress: 1 - backEvent.progress,
    );
  }

  @override
  void handleCommitBackGesture() {
    if (!_tracking) return;
    _tracking = false;
    widget.route.handleCommitBackGesture();
    // Committing pops the route, and a gesture released at full progress has
    // nothing left to animate: the pop can finalize before this returns.
    if (mounted) setState(() {});
  }

  @override
  void handleCancelBackGesture() {
    if (!_tracking) return;
    _tracking = false;
    widget.route.handleCancelBackGesture();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
