import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/widgets.dart';

enum HidingDirection { toStart, toTop, toEnd, toBottom }

class SlideFadeVisibility extends StatelessWidget {
  const SlideFadeVisibility({
    super.key,
    required this.visible,
    required this.child,
    required this.direction,
    this.duration = DesignTokens.durationNormal,
  });

  final bool visible;
  final Widget child;
  final HidingDirection direction;

  /// How long the chrome takes to arrive. Leaving is always quicker.
  final Duration duration;

  Offset get endOffset {
    switch (direction) {
      case HidingDirection.toBottom:
        return const Offset(0, 1);
      case HidingDirection.toTop:
        return const Offset(0, -1);
      case HidingDirection.toStart:
        return const Offset(-1, 0);
      case HidingDirection.toEnd:
        return const Offset(1, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion drops the slide and keeps a short fade, so the chrome
    // still announces that it appeared or went away without moving.
    final reduced = context.reducedMotion;

    // Chrome on its way out of the way should not hold the eye as long as
    // chrome coming in to be used, so the two legs are not symmetric.
    final leaving = !visible;
    final travel = reduced
        ? Duration.zero
        : leaving
        ? DesignTokens.durationFast
        : duration;
    final fade = reduced
        ? DesignTokens.durationFade
        : leaving
        ? DesignTokens.durationFast
        : duration;
    final curve = leaving
        ? DesignTokens.curveAccelerate
        : DesignTokens.curveStandard;

    return RepaintBoundary(
      child: AnimatedSlide(
        curve: curve,
        duration: travel,
        offset: visible ? Offset.zero : endOffset,
        child: AnimatedOpacity(
          curve: curve,
          duration: fade,
          opacity: visible ? 1 : 0,
          child: IgnorePointer(ignoring: !visible, child: child),
        ),
      ),
    );
  }
}
