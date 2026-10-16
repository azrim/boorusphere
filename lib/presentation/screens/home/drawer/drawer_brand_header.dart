import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Brand header: mark, wordmark, tagline, and the theme quick-action.
class HomeDrawerHeader extends ConsumerWidget {
  const HomeDrawerHeader({super.key});

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingLg,
        DesignTokens.spacingLg,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
            child: Image.asset('assets/icons/exported/logo.png', height: 24),
          ),
          const SizedBox(width: DesignTokens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Boorusphere',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.titleLarge,
                ),
                Text(
                  context.t.sidebar.tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(_themeIconOf(themeMode)),
            onPressed: () =>
                ref.read(uiSettingStateProvider.notifier).cycleThemeMode(),
          ),
        ],
      ),
    );
  }
}
