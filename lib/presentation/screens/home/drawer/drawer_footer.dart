import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_updater.dart';
import 'package:boorusphere/presentation/provider/app_versions/app_versions_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_icon_chip.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_tile.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pinned footer: app version, update status, and the About entry point.
class DrawerFooter extends ConsumerWidget {
  const DrawerFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final appVersions = ref.watch(appVersionsStateProvider);
    final updateProgress = ref.watch(appUpdateProgressProvider);

    final currentTile = DrawerTile(
      icon: Icons.info_outline,
      label: appVersions.maybeWhen(
        data: (data) => 'Boorusphere ${data.current}',
        orElse: () => 'Boorusphere',
      ),
      onTap: () => context.router.push(const AboutRoute()),
    );

    final tile = appVersions.maybeWhen(
      data: (data) {
        if (!data.latest.isNewerThan(data.current)) return currentTile;
        if (updateProgress.status.isDownloading) {
          return DrawerTile(
            leading: const SizedBox(
              width: DesignTokens.iconChipSize,
              height: DesignTokens.iconChipSize,
              child: Padding(
                padding: EdgeInsets.all(6),
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
            label: context.t.updater.available(version: '${data.latest}'),
            subtitle: context.t.updater.progress(
              progress: updateProgress.progress,
            ),
            onTap: () => context.router.push(const AboutRoute()),
          );
        }
        return DrawerTile(
          leading: const DrawerIconChip(Icons.info_outline),
          label: context.t.updater.available(version: '${data.latest}'),
          subtitle: updateProgress.status.isDownloaded
              ? context.t.updater.install
              : context.t.changelog.view,
          onTap: () => context.router.push(const AboutRoute()),
        );
      },
      orElse: () => currentTile,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: scheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
            vertical: DesignTokens.spacingSm,
          ),
          child: tile,
        ),
      ],
    );
  }
}
