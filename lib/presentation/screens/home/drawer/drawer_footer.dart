import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_updater.dart';
import 'package:boorusphere/presentation/provider/app_versions/app_versions_state.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_tile.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/confirm_destructive.dart';
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
    final updateId = ref.watch(appUpdaterProvider);
    final updateProgress = ref.watch(appUpdateProgressProvider);
    final updateEntry = ref.watch(
      downloadEntryStateProvider.select((it) => it.getById(updateId)),
    );
    // The installed version is local. Reading it from the updater check would
    // leave the readout blank until that request answers.
    final version = ref.watch(envRepoProvider).appVersion;

    final updateTile = appVersions.maybeWhen(
      data: (data) {
        if (!data.latest.isNewerThan(data.current)) return null;
        final inFlight =
            updateProgress.status.isDownloading ||
            updateProgress.status.isPending;
        if (inFlight) {
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
        // A task restored from an older release cannot install this one.
        final hasUpdateApk =
            updateProgress.status.isDownloaded &&
            updateEntry.dest == updateApkFileName(data.latest);
        return DrawerTile(
          icon: Icons.info_outline,
          label: context.t.updater.available(version: '${data.latest}'),
          subtitle: hasUpdateApk
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
                onTap: () => unawaited(_showExitDialog(context)),
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
            child: ConstrainedBox(
              // The readout is a link, so it gets a full-height tap target
              // instead of the height of its 11 sp line.
              constraints: const BoxConstraints(
                minHeight: DesignTokens.controlHeightMin,
              ),
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
                      'Boorusphere $version',
                      style: context.theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _showExitDialog(BuildContext context) async {
  final confirmed = await confirmDestructive(
    context,
    icon: Icons.logout,
    title: context.t.exit,
    message: context.t.exitConfirmation,
    confirmLabel: context.t.exit,
  );
  if (confirmed) unawaited(SystemNavigator.pop());
}
