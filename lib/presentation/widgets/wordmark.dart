import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// The name as a brand lockup: the display face closed by a primary
/// exclamation mark. The drawer header and the About page both sign with it,
/// so the mark cannot drift between them.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.textStyle});

  /// Base style for the name. The lockup applies the display face, weight and
  /// tracking itself; callers only pick the size.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final base = (textStyle ?? context.theme.textTheme.headlineSmall!).copyWith(
      color: scheme.onSurface,
      fontFamily: AppTypography.displayFamily,
      fontWeight: AppTypography.semiBold,
      letterSpacing: -0.6,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Boorusphere', style: base),
          TextSpan(
            text: '!',
            style: base.copyWith(
              color: scheme.primary,
              // The wordmark is set tight; the mark needs its own air.
              letterSpacing: 0,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
