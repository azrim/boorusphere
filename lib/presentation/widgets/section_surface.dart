import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Rounded surface that groups related rows into one block.
///
/// The container owns the only border and paints `surfaceContainerHigh`, the
/// tone two steps off the page, so a block reads as raised instead of drawn
/// on; rows inside stay flat and transparent.
class SectionSurface extends StatelessWidget {
  const SectionSurface({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    // Midnight paints the page black on purpose; a block there stays on the
    // page tone and is separated by its hairline alone. Every other theme
    // lifts the block a step so the grouping reads at a glance.
    final flat = AppSurfacePolicy.of(context).flat;

    return Material(
      color: flat ? scheme.surface : scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
