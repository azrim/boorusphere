import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.settings.lang.title)),
      body: const SafeArea(child: _Content()),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const subtitlePadding = EdgeInsets.only(top: 8);

    updateLocale(AppLocale? locale) async {
      await ref.read(uiSettingStateProvider.notifier).setLocale(locale);
      Future.delayed(const Duration(milliseconds: 120), () {
        if (context.mounted) {
          context.router.maybePop();
        }
      });
    }

    final current = ref.watch(uiSettingStateProvider.select((ui) => ui.locale));

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
      children: [
        const SizedBox(height: DesignTokens.spacingMd),
        TileGroup(
          children: [
            ListTile(
              title: Text(context.t.auto),
              subtitle: Padding(
                padding: subtitlePadding,
                child: Text(context.t.settings.lang.auto),
              ),
              selected: current == null,
              trailing: current == null
                  ? Icon(Icons.check, color: context.colorScheme.primary)
                  : null,
              onTap: () {
                updateLocale(null);
              },
            ),
            ...AppLocale.values.map((locale) {
              final selected = current == locale;
              final name = locale.translations.languageName;
              final alias = locale.translations.languageAlias;
              return ListTile(
                title: Text(name),
                // The alias repeats the name for several locales; only show it
                // when it adds a second spelling.
                subtitle: alias == name
                    ? null
                    : Padding(padding: subtitlePadding, child: Text(alias)),
                selected: selected,
                trailing: selected
                    ? Icon(Icons.check, color: context.colorScheme.primary)
                    : null,
                onTap: () {
                  updateLocale(locale);
                },
              );
            }),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingLg),
      ],
    );
  }
}
