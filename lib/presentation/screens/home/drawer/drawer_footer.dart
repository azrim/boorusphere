import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_updater.dart';
import 'package:boorusphere/presentation/provider/app_versions/app_versions_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_tile.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pinned footer: exit, the update status when one is available, and the
/// version readout that opens About.
class DrawerFooter extends ConsumerWidget {
  const DrawerFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final appVersions = ref.watch(appVersionsStateProvider);
    final updateProgress = ref.watch(appUpdateProgressProvider);
    final version = appVersions.maybeWhen(
      data: (data) => data.current,
      orElse: () => null,
    );

    final updateTile = appVersions.maybeWhen(
      data: (data) {
        if (!data.latest.isNewerThan(data.current)) return null;
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
          icon: Icons.info_outline,
          label: context.t.updater.available(version: '${data.latest}'),
          subtitle: updateProgress.status.isDownloaded
              ? context.t.updater.install
              : context.t.changelog.view,
          onTap: () => context.router.push(const AboutRoute()),
        );
      },
      orElse: () => null,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: scheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spacingMd,
            DesignTokens.spacingSm,
            DesignTokens.spacingMd,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (updateTile != null) updateTile,
              DrawerTile(
                icon: Icons.logout,
                label: context.t.exit,
                danger: true,
                onTap: () => _showExitDialog(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spacingMd,
            DesignTokens.spacingXs,
            DesignTokens.spacingMd,
            DesignTokens.spacingMd,
          ),
          child: InkWell(
            onTap: () => context.router.push(const AboutRoute()),
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingSm,
                vertical: DesignTokens.spacingXs,
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacingSm),
                  Text(
                    version == null ? 'Boorusphere' : 'Boorusphere $version',
                    style: context.theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void _showExitDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t.exit),
      content: Text(context.t.exitConfirmation),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.cancel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            SystemNavigator.pop();
          },
          child: Text(context.t.exit),
        ),
      ],
    ),
  );
}
