import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.icon,
    required this.children,
    this.margin,
  });

  final Widget icon;
  final Widget children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    // A notice is a block, not a floating card: it takes the section block
    // treatment — the container tone (the page tone in midnight), a hairline,
    // no shadow — and its icon stays muted so the message leads.
    final flat = AppSurfacePolicy.of(context).flat;

    return Card(
      elevation: 0,
      margin: margin,
      color: flat ? scheme.surface : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.radiusXl),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: IconTheme(
          data: IconThemeData(color: scheme.onSurfaceVariant),
          child: Column(
            children: [
              icon,
              const SizedBox(height: DesignTokens.spacingMd),
              children,
            ],
          ),
        ),
      ),
    );
  }
}
