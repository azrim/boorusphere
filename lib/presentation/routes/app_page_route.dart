import 'package:boorusphere/presentation/routes/predictive_back_scope.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// How a page moves relative to the one it covers.
enum AppPageMotion {
  /// A page opened from another one: it arrives from the direction of travel
  /// while the page it covers steps back.
  forward,

  /// The page the app opens on. It never arrives over anything, so it only has
  /// the stepping-back leg.
  root,

  /// A page that shares its subject with the one below it, so the artwork can
  /// fly between them. It fades in place and leaves the page below alone: two
  /// movements at once would compete with the flight, and the tile the artwork
  /// returns to has to stay where the reader left it.
  shared,
}

/// The app's page transition.
///
/// Movement is a fixed distance in dp, not a share of the screen: a tenth of
/// the width is 36 dp on a phone and 80 dp on a tablet, which reads as two
/// different gestures for the same navigation.
class AppPageRoute<T> extends PageRoute<T> {
  AppPageRoute({
    required this.builder,
    super.settings,
    this.motion = AppPageMotion.forward,
    this.opaque = true,
    this.barrierColor = Colors.transparent,
    this.barrierLabel,
    this.maintainState = true,
  });

  final Widget Function(BuildContext context) builder;

  final AppPageMotion motion;

  @override
  final Color? barrierColor;

  @override
  final String? barrierLabel;

  @override
  final bool maintainState;

  @override
  final bool opaque;

  @override
  Duration get transitionDuration => DesignTokens.durationNormal;

  @override
  Duration get reverseTransitionDuration => DesignTokens.durationNormal;

  /// The page below a shared-subject route holds still.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) =>
      motion != AppPageMotion.shared;

  /// Owned by the route, not built per frame: a [CurvedAnimation] carries a
  /// status listener on its parent, so one created in `build` outlives the
  /// frame that made it.
  late final CurvedAnimation _travel;
  late final CurvedAnimation _fade;
  late final CurvedAnimation _cover;

  @override
  void install() {
    super.install();
    _travel = CurvedAnimation(
      parent: animation!,
      curve: DesignTokens.curveStandard,
      reverseCurve: DesignTokens.curveAccelerate,
    );
    // Opacity lands before movement does. A page that is still translucent
    // when it arrives reads as a ghost sliding in; one that is already solid
    // and settling reads as a surface taking its place.
    _fade = CurvedAnimation(
      parent: animation!,
      curve: const Interval(0.0, 0.6),
    );
    _cover = CurvedAnimation(
      parent: secondaryAnimation!,
      curve: DesignTokens.curveShift,
    );
  }

  @override
  void dispose() {
    _travel.dispose();
    _fade.dispose();
    _cover.dispose();
    super.dispose();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return PredictiveBackScope(
      route: this,
      builder: (context) => _buildMotion(context, child),
    );
  }

  Widget _buildMotion(BuildContext context, Widget child) {
    // While the finger owns the transition nothing is curved. A curve would
    // make the page lag behind the drag and then catch up with it, and the
    // controller's status stays `forward` for the whole gesture, so the
    // reverse curve cannot be selected from it either.
    final gesture = popGestureInProgress;
    final travel = gesture ? animation! : _travel;
    final fade = gesture ? animation! : _fade;
    final cover = gesture ? secondaryAnimation! : _cover;

    // Reduced motion keeps the change of page and drops the travel: opacity
    // alone still says which surface is now in front.
    final page = RepaintBoundary(
      child: FadeTransition(opacity: fade, child: child),
    );
    if (context.reducedMotion) return page;

    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return page;

    Widget moved = page;
    if (motion != AppPageMotion.root) {
      moved = SlideTransition(
        position: Tween(
          begin: Offset(DesignTokens.motionPageTravel / width, 0),
          end: Offset.zero,
        ).animate(travel),
        child: moved,
      );
    }
    if (motion != AppPageMotion.shared) {
      // The covered page stays opaque. Fading it would show the window
      // background through it, which is a hole rather than a depth change.
      moved = SlideTransition(
        position: Tween(
          begin: Offset.zero,
          end: Offset(-DesignTokens.motionPageRecede / width, 0),
        ).animate(cover),
        child: moved,
      );
    }
    return moved;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }
}
