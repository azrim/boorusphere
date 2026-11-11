import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Whether the surface a route is bringing in has landed, so its chrome may
/// arrive after the subject rather than alongside it.
///
/// [handover] is the share of the arrival the subject gets to itself. Pass the
/// route's own animation; `null` means there is no route to wait for, and
/// [enabled] false means there is no arrival to hand over from.
bool useSurfaceLanded(
  Animation<double>? routeAnimation, {
  required double handover,
  bool enabled = true,
}) => use(_SurfaceLandedHook(routeAnimation, handover, enabled));

class _SurfaceLandedHook extends Hook<bool> {
  const _SurfaceLandedHook(this.animation, this.handover, this.enabled);

  final Animation<double>? animation;
  final double handover;
  final bool enabled;

  @override
  HookState<bool, _SurfaceLandedHook> createState() => _SurfaceLandedState();
}

class _SurfaceLandedState extends HookState<bool, _SurfaceLandedHook> {
  bool _landed = false;

  @override
  void initHook() {
    super.initHook();
    _attach();
  }

  @override
  void didUpdateHook(_SurfaceLandedHook oldHook) {
    super.didUpdateHook(oldHook);
    if (oldHook.animation == hook.animation &&
        oldHook.enabled == hook.enabled) {
      return;
    }
    oldHook.animation?.removeListener(_sync);
    _attach();
  }

  void _attach() {
    final animation = hook.animation;
    if (!hook.enabled || animation == null) {
      _landed = true;
      return;
    }
    _landed = false;
    animation.addListener(_sync);
    // A route's animation is a parentless proxy on the frame the route is
    // installed, and a parentless proxy reads 1.0. Believing that reading
    // would open the gate before the push has started, and the chrome would
    // flash in and out again while the subject was still leaving. So the gate
    // is answered by the animation itself, plus one reading taken after the
    // frame that installed it — which is also the only reading a route added
    // without a transition ever gets.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) _sync();
    });
  }

  void _sync() {
    final animation = hook.animation;
    if (animation == null) return;
    final landed = animation.value >= hook.handover;
    if (landed == _landed) return;
    setState(() => _landed = landed);
  }

  @override
  void dispose() => hook.animation?.removeListener(_sync);

  @override
  bool build(BuildContext context) => _landed;

  @override
  String get debugLabel => 'useSurfaceLanded';
}
