import 'package:boorusphere/presentation/theme/design_tokens.dart';
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
    return Card(
      elevation: 0,
      margin: margin,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusXl)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          children: [
            icon,
            const SizedBox(height: DesignTokens.spacingMd),
            children,
          ],
        ),
      ),
    );
  }
}
