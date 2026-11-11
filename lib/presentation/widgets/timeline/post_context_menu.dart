import 'dart:math' as math;
import 'dart:ui';

import 'package:boorusphere/presentation/theme/app_surfaces.dart';
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

/// Fixed geometry of the menu card.
///
/// A context menu is a list of verbs, not a panel: it stays narrow enough to
/// sit beside the finger and short enough that the grid behind it is still the
/// thing being looked at.
const double _kCardRadius = DesignTokens.radiusXl;
const double _kCardMaxWidth = 232;
const double _kChipSize = 24;

/// Backdrop blur radius and scrim opacity once fully revealed.
///
/// The blur covers the screen so the menu reads as a layer above it, but it is
/// thin: the grid has to stay recognisable, not disappear.
const double _kBackdropBlur = 11;
const double _kBackdropOpacity = 0.16;

/// Shows the post context menu as a floating card over a blurred,
/// tap-to-dismiss backdrop, resolving to the tapped action (or `null` when
/// dismissed).
///
/// [groups] render top-to-bottom with a hairline divider between them; rows
/// fade and slide in with a short stagger.
Future<PostContextMenuAction?> showPostContextMenu(
  BuildContext context, {
  required List<List<PostContextMenuEntry>> groups,
  Offset? position,
}) {
  return showGeneralDialog<PostContextMenuAction>(
    context: context,
    // Dismissible so the barrier exposes a dismiss action to screen readers;
    // the backdrop below still handles the pointer tap.
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // Reduced motion keeps the route's fade at the short window and drops the
    // travel and the stagger below, so the menu still reads as arriving.
    transitionDuration: context.reducedMotion
        ? DesignTokens.durationFade
        : DesignTokens.durationNormal,
    pageBuilder: (context, animation, secondaryAnimation) {
      return _ContextMenuView(
        animation: animation,
        groups: groups,
        position: position,
      );
    },
  );
}

double _clamp01(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);

class _ContextMenuView extends StatefulWidget {
  const _ContextMenuView({
    required this.animation,
    required this.groups,
    this.position,
  });

  final Animation<double> animation;
  final List<List<PostContextMenuEntry>> groups;

  /// Where the finger went down, in global coordinates. The card opens beside
  /// that point the way a desktop menu opens at the cursor; without it (a
  /// screen-reader long-press) the card is centred.
  final Offset? position;

  @override
  State<_ContextMenuView> createState() => _ContextMenuViewState();
}

class _ContextMenuViewState extends State<_ContextMenuView> {
  /// Created once for the route's animation and disposed with it, never in
  /// `build`: a curve wrapper attaches a status listener that only `dispose`
  /// removes.
  late final CurvedAnimation _card = CurvedAnimation(
    parent: widget.animation,
    curve: DesignTokens.curveStandard,
    reverseCurve: DesignTokens.curveAccelerate,
  );

  @override
  void dispose() {
    _card.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final travel = context.reducedMotion
        ? 0.0
        : DesignTokens.motionChromeTravel;

    return Stack(
      children: [
        Positioned.fill(
          child: _MenuBackdrop(onTap: () => Navigator.of(context).pop()),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _MenuLayout(
              anchor: widget.position,
              margin: DesignTokens.spacingMd,
            ),
            child: AnimatedBuilder(
              animation: _card,
              builder: (context, child) {
                final t = _clamp01(_card.value);
                // Only the travel is animated here. The fade belongs to the
                // route, which fades the backdrop and the card together, so
                // the blur cannot arrive after the menu it belongs to.
                return Transform.translate(
                  offset: Offset(0, travel * (1 - t)),
                  child: child,
                );
              },
              child: _MenuCard(
                animation: widget.animation,
                groups: widget.groups,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Blurs and dims the app behind the menu, and dismisses it on tap.
///
/// Both the blur and the veil are painted at full strength from the first
/// frame: the dialog route already fades the whole page in, and animating the
/// blur as well multiplied two fades into one late blur.
class _MenuBackdrop extends StatelessWidget {
  const _MenuBackdrop({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scrim = context.colorScheme.scrim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _kBackdropBlur,
          sigmaY: _kBackdropBlur,
        ),
        child: ColoredBox(color: scrim.withValues(alpha: _kBackdropOpacity)),
      ),
    );
  }
}

/// Places the card beside the point that opened it and keeps it on screen.
///
/// The menu opens to the lower right of the finger, the way a desktop context
/// menu opens at the cursor, and flips to the other side of that point when
/// the preferred corner would push it past the margin.
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.anchor, required this.margin});

  final Offset? anchor;
  final double margin;

  static const double _gap = 6;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final point = anchor;
    if (point == null) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }

    var dx = point.dx + _gap;
    var dy = point.dy + _gap;
    if (dx + childSize.width > size.width - margin) {
      dx = point.dx - childSize.width - _gap;
    }
    if (dy + childSize.height > size.height - margin) {
      dy = point.dy - childSize.height - _gap;
    }

    final maxX = math.max(margin, size.width - childSize.width - margin);
    final maxY = math.max(margin, size.height - childSize.height - margin);
    return Offset(dx.clamp(margin, maxX), dy.clamp(margin, maxY));
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.margin != margin;
}

/// The floating card holding the grouped menu rows.
class _MenuCard extends StatefulWidget {
  const _MenuCard({required this.animation, required this.groups});

  final Animation<double> animation;
  final List<List<PostContextMenuEntry>> groups;

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> {
  /// One stagger wrapper per row, built once and disposed with the card. A
  /// wrapper per build re-registered its intervals on the route animation on
  /// every rebuild of the card.
  late final List<CurvedAnimation> _rowAnimations = _buildRowAnimations();

  List<CurvedAnimation> _buildRowAnimations() {
    final count = widget.groups.fold<int>(0, (sum, it) => sum + it.length);
    return [for (var index = 0; index < count; index++) _rowAnimation(index)];
  }

  @override
  void dispose() {
    for (final animation in _rowAnimations) {
      animation.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final flat = AppSurfacePolicy.of(context).flat;
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
          child: Container(
            decoration: BoxDecoration(
              // Opaque, and no blur of its own: the backdrop already blurs the
              // app behind the menu, so a second blur under a fill that is
              // nearly solid costs raster time with nothing left to show for it.
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(_kCardRadius),
              // The card floats on its own shadow; only midnight needs an
              // edge, where the tone and the shadow draw nothing on black.
              border: flat
                  ? Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    )
                  : null,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingXs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var g = 0; g < widget.groups.length; g++) ...[
                      if (g > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: DesignTokens.spacingSm,
                          endIndent: DesignTokens.spacingSm,
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      for (final entry in widget.groups[g])
                        _MenuRowTile(
                          entry: entry,
                          animation: _rowAnimations[rowIndex++],
                          onTap: () => Navigator.of(context).pop(entry.action),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Staggered entrance for the row at [index].
  CurvedAnimation _rowAnimation(int index) {
    final start = 0.08 + index * 0.075;
    final end = math.min(start + 0.5, 1.0);
    return CurvedAnimation(
      parent: widget.animation,
      curve: Interval(start, end, curve: DesignTokens.curveStandard),
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

    // Reduced motion takes the whole stagger away: the rows are already there
    // when the card fades in, so nothing here listens to the route.
    final entrance = context.reducedMotion
        ? kAlwaysCompleteAnimation
        : animation;

    return AnimatedBuilder(
      animation: entrance,
      builder: (context, child) {
        final t = _clamp01(entrance.value);
        // A row whose entrance has not started is invisible; an invisible
        // control must not answer a tap or read out to a screen reader.
        return IgnorePointer(
          ignoring: t == 0,
          child: ExcludeSemantics(
            excluding: t == 0,
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, DesignTokens.motionChromeTravel * (1 - t)),
                child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
              ),
            ),
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
            constraints: const BoxConstraints(
              minHeight: DesignTokens.controlHeightMin,
            ),
            child: Row(
              children: [
                const SizedBox(width: DesignTokens.spacingSm),
                Container(
                  width: _kChipSize,
                  height: _kChipSize,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: Icon(entry.icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: DesignTokens.spacingSm),
                Expanded(
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.textTheme.labelLarge?.copyWith(
                      color: labelColor,
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spacingSm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
