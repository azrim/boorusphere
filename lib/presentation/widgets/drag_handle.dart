import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// The sheet grab bar is a Material shape, not a block in the spacing scale:
/// short enough to read as a handle, thick enough to stay visible when the
/// sheet is dark.
const double _kHandleWidth = 40.0;
const double _kHandleHeight = 4.0;

/// M3 paints the grab bar as a translucent `onSurfaceVariant`. The alpha is
/// named because it is the one thing that keeps the bar off the sheet's edge.
const double _kHandleAlpha = 0.4;

/// Standard bottom-sheet drag handle used across the app.
///
/// Renders a 40×4 rounded bar centered horizontally. Pass [margin] to
/// control vertical spacing around the handle (defaults to the sheet shell's
/// own: 8 dp above and 4 dp below).
class DragHandle extends StatelessWidget {
  const DragHandle({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin:
            margin ??
            const EdgeInsets.only(
              top: DesignTokens.spacingSm,
              bottom: DesignTokens.spacingXs,
            ),
        width: _kHandleWidth,
        height: _kHandleHeight,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: _kHandleAlpha),
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
      ),
    );
  }
}
