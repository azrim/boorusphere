import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_icon_chip.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Action row: leading icon chip, label with optional subtitle, and trailing.
///
/// [leading] replaces the default icon chip (e.g. a progress spinner);
/// [danger] tints the label and chip with the error colors.
class DrawerTile extends StatelessWidget {
  const DrawerTile({
    super.key,
    this.icon,
    required this.label,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.danger = false,
  }) : assert(icon != null || leading != null);

  final IconData? icon;
  final String label;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final labelColor = danger ? scheme.error : scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
        child: Row(
          children: [
            leading ?? DrawerIconChip(icon!, danger: danger),
            const SizedBox(width: DesignTokens.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.textTheme.bodyMedium?.copyWith(
                      color: labelColor,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: DesignTokens.spacingSm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
