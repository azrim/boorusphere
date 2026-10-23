import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Action row: leading icon, label with optional subtitle, and trailing.
///
/// [leading] replaces the default icon (e.g. a progress spinner or a tinted
/// icon); [danger] tints the label and icon with the error colors.
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

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: DesignTokens.controlHeightMin,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingSm,
            vertical: DesignTokens.spacingSm,
          ),
          child: Row(
            children: [
              leading ??
                  Icon(
                    icon!,
                    size: DesignTokens.iconInline,
                    color: danger ? scheme.error : scheme.onSurfaceVariant,
                  ),
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
                      style: context.theme.textTheme.bodyLarge?.copyWith(
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
      ),
    );
  }
}
