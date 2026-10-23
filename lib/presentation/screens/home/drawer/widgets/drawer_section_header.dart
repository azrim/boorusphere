import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/section_label.dart';
import 'package:flutter/material.dart';

/// Drawer section label with an optional count and a trailing action.
class DrawerSectionHeader extends StatelessWidget {
  const DrawerSectionHeader(this.label, {super.key, this.count, this.action});

  final String label;
  final int? count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final countStyle = context.theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.only(
        top: DesignTokens.spacingMd,
        bottom: DesignTokens.spacingSm,
      ),
      child: Row(
        children: [
          SectionLabel(label),
          if (count != null) ...[
            const SizedBox(width: DesignTokens.spacingSm),
            Text('$count', style: countStyle),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}
