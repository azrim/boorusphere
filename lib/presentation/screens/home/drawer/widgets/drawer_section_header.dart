import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:flutter/material.dart';

/// Small-caps section label with a hairline underline, an optional count, and
/// a trailing action.
///
/// The underline hugs the label instead of the row so a tall trailing action
/// never stretches it.
class DrawerSectionHeader extends StatelessWidget {
  const DrawerSectionHeader(this.label, {super.key, this.count, this.action});

  final String label;
  final int? count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final labelStyle = context.theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.only(
        top: DesignTokens.spacingLg,
        bottom: DesignTokens.spacingSm,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: DesignTokens.spacingXs + 2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Text(label.toUpperLocale(context), style: labelStyle),
          ),
          if (count != null) ...[
            const SizedBox(width: DesignTokens.spacingSm),
            Text(
              '$count',
              style: labelStyle?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}
