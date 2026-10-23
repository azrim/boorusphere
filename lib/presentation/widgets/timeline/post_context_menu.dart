import 'dart:math' as math;
import 'dart:ui';

import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Actions offered by the long-press context menu on a timeline card.
enum PostContextMenuAction { select, favorite, download, share, source }

/// One tappable row in the [showPostContextMenu] card.
class PostContextMenuEntry {
  const PostContextMenuEntry({
    required this.action,
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  final PostContextMenuAction action;
  final IconData icon;
  final String label;

  /// Dimmed and non-tappable when false (e.g. share/source without a link).
  final bool enabled;
}

/// Spring entrance curve for the floating card: a quick overshoot that settles.
const Curve _kSpringCurve = Cubic(0.34, 1.56, 0.64, 1);

/// Fixed geometry of the menu card.
const double _kRowHeight = 48;
const double _kCardRadius = 24;
const double _kCardMaxWidth = 320;

/// Backdrop blur radius and scrim opacity once fully revealed.
const double _kBackdropBlur = 20;
const double _kBackdropOpacity = 0.6;

/// The backdrop blur is quantised into this many steps. The engine caches a
/// blurred backdrop per filter, so a continuously changing sigma re-blurs the
/// whole screen on every frame of the entrance; six steps still read as a
/// progressive blur and cost six rasterisations instead of ~18.
const int _kBackdropBlurSteps = 6;

double _steppedBackdropBlur(double t) {
  final step = (t * _kBackdropBlurSteps).round() / _kBackdropBlurSteps;
  return _kBackdropBlur * step.clamp(0.0, 1.0);
}

/// Same idea for the card: a quantised sigma lets the engine reuse a cached
/// filter during the entrance instead of re-rasterising every frame.
double _quantizedBlur(double value) {
  const steps = 5;
  return (value * steps).round() / steps;
}

/// Shows the post context menu as a floating glass card over a blurred,
/// tap-to-dismiss backdrop, resolving to the tapped action (or `null` when
/// dismissed).
///
/// [groups] render top-to-bottom with a hairline divider between them; rows
/// fade and slide in with a short stagger.
Future<PostContextMenuAction?> showPostContextMenu(
  BuildContext context, {
  required List<List<PostContextMenuEntry>> groups,
}) {
  return showGeneralDialog<PostContextMenuAction>(
    context: context,
    // Dismissible so the barrier exposes a dismiss action to screen readers;
    // the blurred backdrop below still handles the pointer tap.
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: context.motionDuration(DesignTokens.durationNormal),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _ContextMenuView(animation: animation, groups: groups);
    },
  );
}

double _clamp01(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);

class _ContextMenuView extends StatelessWidget {
  const _ContextMenuView({required this.animation, required this.groups});

  final Animation<double> animation;
  final List<List<PostContextMenuEntry>> groups;

  @override
  Widget build(BuildContext context) {
    final backdrop = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    final card = CurvedAnimation(
      parent: animation,
      curve: _kSpringCurve,
      reverseCurve: Curves.easeInCubic,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: _MenuBackdrop(
            animation: backdrop,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Center(
          child: AnimatedBuilder(
            animation: card,
            builder: (context, child) {
              final t = card.value;
              final blur = _quantizedBlur(math.max(0.0, 1 - t) * 10);
              return Opacity(
                opacity: _clamp01(t),
                child: Transform.translate(
                  offset: Offset(0, 18 * (1 - t)),
                  child: Transform.scale(
                    scale: 0.82 + 0.18 * t,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: _MenuCard(animation: animation, groups: groups),
          ),
        ),
      ],
    );
  }
}

/// Full-screen scrim that blurs the app behind the menu and dismisses it on tap.
class _MenuBackdrop extends StatelessWidget {
  const _MenuBackdrop({required this.animation, required this.onTap});

  final Animation<double> animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scrim = context.colorScheme.scrim;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = _clamp01(animation.value);
        final veil = ColoredBox(
          color: scrim.withValues(alpha: _kBackdropOpacity * t),
        );
        final blur = _steppedBackdropBlur(t);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // Skip the blur pass entirely at the endpoints, where it would be a
          // no-op layer that still costs a full-screen rasterisation.
          child: blur <= 0
              ? veil
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: veil,
                ),
        );
      },
    );
  }
}

/// The floating glass card holding the grouped menu rows.
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.animation, required this.groups});

  final Animation<double> animation;
  final List<List<PostContextMenuEntry>> groups;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final width = math.min(
      context.mqSize.width - DesignTokens.spacingXl,
      _kCardMaxWidth,
    );

    var rowIndex = 0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kCardRadius),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.5),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kCardRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(_kCardRadius),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var g = 0; g < groups.length; g++) ...[
                        if (g > 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            indent: DesignTokens.spacingSm,
                            endIndent: DesignTokens.spacingSm,
                            color: scheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        for (final entry in groups[g])
                          _MenuRowTile(
                            entry: entry,
                            animation: _rowAnimation(rowIndex++),
                            onTap: () =>
                                Navigator.of(context).pop(entry.action),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Staggered entrance for the row at [index].
  Animation<double> _rowAnimation(int index) {
    final start = 0.08 + index * 0.075;
    final end = math.min(start + 0.5, 1.0);
    return CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }
}

/// A single menu row: tinted icon chip, label, and press feedback.
class _MenuRowTile extends StatelessWidget {
  const _MenuRowTile({
    required this.entry,
    required this.animation,
    required this.onTap,
  });

  final PostContextMenuEntry entry;
  final Animation<double> animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final enabled = entry.enabled;
    final labelColor = enabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.38);
    final iconBackground = enabled
        ? scheme.secondaryContainer
        : scheme.onSurface.withValues(alpha: 0.08);
    final iconColor = enabled
        ? scheme.onSecondaryContainer
        : scheme.onSurface.withValues(alpha: 0.38);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = _clamp01(animation.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - t)),
            child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
          ),
        );
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          onTap: enabled ? onTap : null,
          // A minimum instead of a fixed height, so a large font scale grows
          // the row instead of clipping the label.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _kRowHeight),
            child: Row(
              children: [
                const SizedBox(
                  width: DesignTokens.spacingSm + DesignTokens.spacingXs,
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                  child: Icon(entry.icon, size: 16, color: iconColor),
                ),
                const SizedBox(
                  width: DesignTokens.spacingSm + DesignTokens.spacingXs,
                ),
                Expanded(
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.textTheme.labelLarge?.copyWith(
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(
                  width: DesignTokens.spacingSm + DesignTokens.spacingXs,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
