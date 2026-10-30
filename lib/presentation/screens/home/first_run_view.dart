import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:boorusphere/presentation/widgets/section_label.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
import 'package:boorusphere/presentation/widgets/wordmark.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The screen a new install opens on.
///
/// It is the server list with no server in it: the presets are the page, so
/// the first decision is a pick rather than a page explaining what a server
/// is. Picking one adds it and the grid opens on it; scanning an address stays
/// one row away for anyone whose booru is not in the list.
class FirstRunView extends ConsumerWidget {
  const FirstRunView({super.key});

  /// Presets shown before the section sends the reader to the full list:
  /// enough to cover the boorus most people are looking for, short enough that
  /// the add row still sits above the fold on a phone.
  static const int presetLimit = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaults = ref.watch(serverRepoProvider.select((it) => it.defaults));
    final presets = defaults.values.take(presetLimit).toList();
    final roles = AppTextRoles.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          DesignTokens.spacingLg,
          DesignTokens.spacingMd,
          DesignTokens.spacingXl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Wordmark(textStyle: context.theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: DesignTokens.spacingXl),
            Text(
              context.t.onboarding.question,
              style: context.theme.textTheme.titleLarge,
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            Text(context.t.onboarding.welcomeDesc, style: roles.rowSupporting),
            SectionHeading(
              context.t.servers.select,
              action: defaults.length > presetLimit
                  ? TextButton(
                      onPressed: () => context.router.push(ServerPresetRoute()),
                      child: Text(context.t.onboarding.browsePresets),
                    )
                  : null,
            ),
            TileGroup(
              children: [
                for (final server in presets)
                  ListTile(
                    leading: Favicon(url: server.homepage),
                    title: Text(server.name),
                    subtitle: RowSubtitle(Text(server.homepage)),
                    onTap: () => unawaited(_pick(context, ref, server)),
                  ),
                ListTile(
                  leading: Icon(Icons.add, color: context.colorScheme.primary),
                  title: Text(context.t.onboarding.addFirstServer),
                  onTap: () => context.router.push(const ServerAddRoute()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, Server server) async {
    try {
      await ref.read(serverStateProvider.notifier).add(server);
    } catch (e, stack) {
      mainLog.e('First run: failed to add ${server.key}', e, stack);
      if (!context.mounted) return;
      showToast(context, context.t.error.unknown);
      return;
    }

    if (!context.mounted) return;
    // This page was built for the session it had before any server existed, so
    // its state would resolve no server at all. A fresh page opens the grid on
    // the one just picked.
    await context.router.replaceAll([
      HomeRoute(session: SearchSession(serverId: server.id)),
    ]);
  }
}
