import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// Standard bottom-sheet drag handle used across the app.
///
/// Renders a 40×4 rounded bar centered horizontally. Pass [margin] to
/// control vertical spacing around the handle (defaults to top 4, bottom 8).
class DragHandle extends StatelessWidget {
  const DragHandle({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: margin ?? const EdgeInsets.only(top: 4, bottom: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
      ),
    );
  }
}
