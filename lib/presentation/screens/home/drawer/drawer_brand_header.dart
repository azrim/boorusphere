import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Brand header: an eyebrow tagline above the wordmark, and the theme
/// quick-action on the trailing edge.
class HomeDrawerHeader extends ConsumerWidget {
  const HomeDrawerHeader({super.key});

  String _themeLabelOf(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return context.t.sidebar.themeDark;
      case ThemeMode.light:
        return context.t.sidebar.themeLight;
      default:
        return context.t.sidebar.themeSystem;
    }
  }

  IconData _themeIconOf(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return Icons.brightness_2;
      case ThemeMode.light:
        return Icons.brightness_high;
      default:
        return Icons.brightness_auto;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final themeMode = ref.watch(
      uiSettingStateProvider.select((ui) => ui.themeMode),
    );
    final wordmark = context.theme.textTheme.headlineSmall?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w500,
      letterSpacing: -1.2,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingLg,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.t.sidebar.tagline.toUpperLocale(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingSm),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Boorusphere', style: wordmark),
                      TextSpan(
                        text: '.',
                        style: wordmark?.copyWith(color: scheme.primary),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          IconButton(
            icon: Icon(_themeIconOf(themeMode)),
            tooltip: _themeLabelOf(context, themeMode),
            onPressed: () =>
                ref.read(uiSettingStateProvider.notifier).cycleThemeMode(),
            style: IconButton.styleFrom(
              foregroundColor: scheme.primary,
              iconSize: DesignTokens.iconInline,
              side: BorderSide(color: scheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
