import 'dart:math' as math;
import 'dart:ui';

import 'package:boorusphere/presentation/theme/app_typography.dart';
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
const double _kBackdropOpacity = 0.34;

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
            child: _MenuHalo(
              animation: card,
              child: _MenuCard(animation: animation, groups: groups),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dismisses the menu on tap and dims the app behind it.
///
/// The dim is all this layer does: the blur belongs to the card (see
/// [_MenuHalo]), so opening one card does not turn the screen into a modal.
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ColoredBox(
            color: scrim.withValues(alpha: _kBackdropOpacity * t),
          ),
        );
      },
    );
  }
}

/// The soft edge around the card: the card's own footprint plus a short
/// margin, blurred, so the artwork directly behind the menu recedes while the
/// rest of the grid stays readable.
class _MenuHalo extends StatelessWidget {
  const _MenuHalo({required this.animation, required this.child});

  /// How far the blur reaches past the card.
  static const double margin = DesignTokens.spacingLg;

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scrim = context.colorScheme.scrim;
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = _clamp01(animation.value);
              final blur = _steppedBackdropBlur(t);
              if (blur <= 0) return const SizedBox.shrink();

              return ClipRRect(
                borderRadius: BorderRadius.circular(_kCardRadius + margin),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: ColoredBox(color: scrim.withValues(alpha: 0.16 * t)),
                ),
              );
            },
          ),
        ),
        Padding(padding: const EdgeInsets.all(margin), child: child),
      ],
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
            // The card floats over the timeline, so its shadow comes from the
            // same tinted colour the rest of the chrome uses.
            BoxShadow(
              color: DesignTokens.shadowColor(scheme),
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
                  padding: const EdgeInsets.all(DesignTokens.spacingSm),
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
                  width: DesignTokens.iconChipSize,
                  height: DesignTokens.iconChipSize,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                  child: Icon(
                    entry.icon,
                    size: DesignTokens.iconInline,
                    color: iconColor,
                  ),
                ),
                const SizedBox(
                  width: DesignTokens.spacingSm + DesignTokens.spacingXs,
                ),
                Expanded(
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextRoles.of(
                      context,
                    ).rowTitle.copyWith(color: labelColor),
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
