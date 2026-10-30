import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/confirm_destructive.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class ServerPage extends ConsumerWidget {
  const ServerPage({super.key, this.session});
  final SearchSession? session;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedServerId = ref.read(
      serverSettingStateProvider.select((it) => it.lastActiveId),
    );
    final session = this.session ?? SearchSession(serverId: savedServerId);

    return ProviderScope(
      overrides: [searchSessionProvider.overrideWith((ref) => session)],
      child: const _Content(),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.servers.title),
        actions: [
          PopupMenuButton(
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            onSelected: (value) async {
              switch (value) {
                case 'reset':
                  final confirmed = await confirmDestructive(
                    context,
                    icon: Icons.restore,
                    title: context.t.resetToDefault,
                    message: context.t.servers.resetWarning,
                    confirmLabel: context.t.reset,
                  );
                  if (confirmed) {
                    await ref.read(serverStateProvider.notifier).reset();
                  }
                  break;
                default:
                  break;
              }
            },
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  value: 'reset',
                  child: Text(context.t.resetToDefault),
                ),
              ];
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
          ),
          children: [
            // The app bar already names the page; a section label repeating it
            // would be a second heading for the same list.
            const SizedBox(height: DesignTokens.spacingMd),
            TileGroup(
              children: [
                ...servers.map((it) {
                  return ListTile(
                    title: Text(it.name),
                    subtitle: RowSubtitle(Text(it.homepage)),
                    leading: Favicon(url: it.homepage),
                    trailing: PopupMenuButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).showMenuTooltip,
                      onSelected: (value) async {
                        switch (value) {
                          case 'edit':
                            await context.router.push(
                              ServerEditorRoute(server: it),
                            );
                            break;
                          case 'remove':
                            if (servers.length == 1) {
                              showToast(
                                context,
                                context.t.servers.removeLastError,
                              );
                              break;
                            }

                            // The drawer asks before removing a server; this
                            // page is the same action and answers the same way.
                            final confirmed = await confirmDestructive(
                              context,
                              title: context.t.remove,
                              message: context.t.servers.removeWarning(
                                name: it.name,
                              ),
                              confirmLabel: context.t.remove,
                            );
                            if (!confirmed) break;
                            await ref
                                .read(serverStateProvider.notifier)
                                .remove(it);
                            break;
                          default:
                            break;
                        }
                      },
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(context.t.edit),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(context.t.remove),
                          ),
                        ];
                      },
                    ),
                  );
                }),
                ListTile(
                  title: Text(context.t.servers.add),
                  leading: Icon(Icons.add, color: context.colorScheme.primary),
                  onTap: () => context.router.push(const ServerAddRoute()),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingLg),
          ],
        ),
      ),
    );
  }
}
