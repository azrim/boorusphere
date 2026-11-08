import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Rounded surface that groups related rows into one block.
///
/// The container paints `surfaceContainerHigh`, the tone two steps off the
/// page, so a block reads as raised by its tone alone; rows inside stay flat
/// and transparent. Midnight keeps a hairline: its blocks sit on the page's
/// black, where a tone step has nothing to lift from.
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
        side: flat ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
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
