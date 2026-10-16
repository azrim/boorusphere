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

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Icon(icon, size: 18, color: fg),
    );
  }
}
