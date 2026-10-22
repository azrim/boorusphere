import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Neutral rounded square that hosts a drawer action icon.
///
/// [danger] tints the chip with the error container for destructive actions;
/// [background] and [foreground] override the tint for one-off states.
class DrawerIconChip extends StatelessWidget {
  const DrawerIconChip(
    this.icon, {
    super.key,
    this.danger = false,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final bool danger;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final bg =
        background ??
        (danger ? scheme.errorContainer : scheme.surfaceContainerHighest);
    final fg =
        foreground ??
        (danger ? scheme.onErrorContainer : scheme.onSurfaceVariant);

    // The chip grows with the user's font scale so a large label never sits
    // next to a chip that looks like it belongs to a smaller type size.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    final size = DesignTokens.iconChipSize * scale;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Icon(icon, size: DesignTokens.iconInline * scale, color: fg),
    );
  }
}
