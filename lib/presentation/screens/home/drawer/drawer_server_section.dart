import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_section_header.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_tile.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/confirm_destructive.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Server switcher: header with count and Manage action, then one row per
/// server and the add-server row.
class DrawerServerSection extends ConsumerWidget {
  const DrawerServerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverStateProvider);
    final session = ref.watch(searchSessionProvider);
    // Falling back to the first server here would mark an unrelated row as the
    // active one, and tapping it would then do nothing: the session still
    // points at a server that no longer exists.
    final activeServer = servers.getById(session.serverId, or: Server.empty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DrawerSectionHeader(
          context.t.sidebar.servers,
          count: servers.length,
          action: _ManageServersButton(session: session),
        ),
        SectionSurface(
          children: [
            ...servers.map((server) {
              return _ServerRow(
                server: server,
                active: server.id == activeServer.id,
                onTap: () {
                  Navigator.of(context).pop();
                  if (server.id != activeServer.id) {
                    context.router.push(
                      HomeRoute(session: session.copyWith(serverId: server.id)),
                    );
                  } else {
                    ref
                        .read(pageStateProvider.notifier)
                        .update((it) => it.copyWith(clear: true));
                  }
                },
                onEdit: () {
                  Navigator.of(context).pop();
                  context.router.push(ServerEditorRoute(server: server));
                },
                onRemove: () => _removeServer(context, ref, server),
              );
            }),
            DrawerTile(
              leading: Icon(
                Icons.add,
                size: DesignTokens.iconInline,
                color: context.colorScheme.primary,
              ),
              label: context.t.sidebar.addCustomServer,
              onTap: () {
                Navigator.of(context).pop();
                context.router.push(const ServerAddRoute());
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Confirms the removal before dropping a server's configuration, and reports
/// the one failure the repo raises: removing the last remaining server.
Future<void> _removeServer(
  BuildContext context,
  WidgetRef ref,
  Server server,
) async {
  final confirmed = await confirmDestructive(
    context,
    title: context.t.remove,
    message: context.t.servers.removeWarning(name: server.name),
    confirmLabel: context.t.remove,
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref.read(serverStateProvider.notifier).remove(server);
  } on Exception {
    if (!context.mounted) return;
    context.scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(context.t.servers.removeLastError),
        duration: DesignTokens.durationSnackbar,
      ),
    );
  }
}

class _ManageServersButton extends StatelessWidget {
  const _ManageServersButton({required this.session});

  final SearchSession session;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        Navigator.of(context).pop();
        context.router.push(ServerRoute(session: session));
      },
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm),
        minimumSize: const Size(0, DesignTokens.controlHeightMin),
        foregroundColor: context.colorScheme.onSurfaceVariant,
        textStyle: context.theme.textTheme.labelMedium,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.t.sidebar.manage),
          const Icon(Icons.chevron_right, size: 16),
        ],
      ),
    );
  }
}

/// One server: favicon, name, and a status dot while it is the active server.
class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.active,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  final Server server;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final foreground = active ? scheme.onSecondaryContainer : scheme.onSurface;

    // The row tap and the per-server menu are two separate actions, so the
    // menu sits outside the merged node. Merging them folds both tap targets
    // into one and leaves edit/remove unreachable from a screen reader.
    return Material(
      color: active ? scheme.secondaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: active
            ? BorderSide(color: scheme.primary.withValues(alpha: 0.45))
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: MergeSemantics(
              child: Semantics(
                selected: active,
                child: InkWell(
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacingSm,
                        vertical: DesignTokens.spacingXs,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: DesignTokens.iconChipSize,
                            height: DesignTokens.iconChipSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(
                                DesignTokens.radiusMd,
                              ),
                              border: Border.all(
                                color: active
                                    ? scheme.primary.withValues(alpha: 0.4)
                                    : scheme.outlineVariant,
                              ),
                            ),
                            child: Favicon(
                              url: server.homepage,
                              shape: BoxShape.circle,
                              size: DesignTokens.iconChipSize,
                              iconSize: DesignTokens.iconAction,
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spacingMd),
                          Expanded(
                            child: Text(
                              server.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.theme.textTheme.bodyMedium
                                  ?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                  break;
                case 'remove':
                  onRemove();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: DesignTokens.iconInline),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Text(context.t.edit),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'remove',
                child: Row(
                  children: [
                    const Icon(Icons.delete, size: DesignTokens.iconInline),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Text(context.t.remove),
                  ],
                ),
              ),
            ],
            iconSize: DesignTokens.iconInline,
            iconColor: active
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
          ),
          const SizedBox(width: DesignTokens.spacingXs),
        ],
      ),
    );
  }
}
