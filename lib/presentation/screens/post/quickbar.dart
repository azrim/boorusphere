import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

class QuickBar extends StatelessWidget {
  factory QuickBar({Key? key, Widget? title}) =>
      QuickBar._(key: key, title: title);
  const QuickBar._({
    super.key,
    this.title,
    this.actionTitle,
    this.onPressed,
    this.useProgressBar = false,
    this.progress,
  });

  factory QuickBar.action({
    Key? key,
    Widget? title,
    Widget? actionTitle,
    required VoidCallback onPressed,
  }) => QuickBar._(
    key: key,
    title: title,
    actionTitle: actionTitle,
    onPressed: onPressed,
  );

  factory QuickBar.progress({Key? key, Widget? title, double? progress}) =>
      QuickBar._(
        key: key,
        title: title,
        progress: progress,
        useProgressBar: true,
      );

  final Widget? title;
  final VoidCallback? onPressed;
  final Widget? actionTitle;
  final double? progress;
  final bool useProgressBar;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final actionTitle = this.actionTitle;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: DesignTokens.controlHeightMin,
        minHeight: DesignTokens.controlHeightMin,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
          color: context.colorScheme.surface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm),
        // The pill hugs its label: a max-width row stretched it across the
        // screen, and a long translated label then overflowed it.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (title != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingMd,
                    vertical: DesignTokens.spacingSm,
                  ),
                  child: DefaultTextStyle(
                    style:
                        context.theme.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurface,
                        ) ??
                        const TextStyle(),
                    child: title,
                  ),
                ),
              ),
            if (actionTitle != null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  textStyle: context.theme.textTheme.bodySmall,
                ),
                onPressed: onPressed,
                child: actionTitle,
              ),
            if (useProgressBar)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                  color: context.theme.colorScheme.surface,
                ),
                padding: const EdgeInsets.all(DesignTokens.spacingSm),
                margin: const EdgeInsets.all(2),
                child: SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(
                      context.colorScheme.primary.withValues(alpha: 0.75),
                    ),
                    value: progress,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static double preferredBottomPosition(BuildContext context) {
    return context.mediaQuery.viewPadding.bottom +
        kBottomNavigationBarHeight +
        DesignTokens.spacingLg;
  }
}
