import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:flutter/material.dart';

/// Rounded block of [ListTile] rows, inset so the rows sit inside the border
/// instead of touching it.
class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SectionSurface(
      children: [
        ListTileTheme(
          data: ListTileThemeData(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingCardInset,
            ),
            minVerticalPadding: DesignTokens.spacingSm,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}
