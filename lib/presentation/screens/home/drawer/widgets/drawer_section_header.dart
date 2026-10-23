import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_badge.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:flutter/material.dart';

/// Uppercase section label with an optional count badge and trailing action.
class DrawerSectionHeader extends StatelessWidget {
  const DrawerSectionHeader(this.label, {super.key, this.count, this.action});

  final String label;
  final int? count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        DesignTokens.spacingMd,
        0,
        DesignTokens.spacingSm,
      ),
      child: Row(
        children: [
          Text(
            label.toUpperLocale(context),
            style: context.theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: DesignTokens.spacingSm),
            DrawerBadge('$count'),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}
