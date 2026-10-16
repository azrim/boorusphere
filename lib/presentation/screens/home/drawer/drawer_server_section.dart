import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_section_header.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Server switcher: header with count and Manage action, the server cards,
/// and the add-server button.
class DrawerServerSection extends ConsumerWidget {
  const DrawerServerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverStateProvider);
    final session = ref.watch(searchSessionProvider);
    final activeServer = servers.getById(session.serverId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DrawerSectionHeader(
          context.t.sidebar.servers,
          count: servers.length,
          action: _ManageServersButton(session: session),
        ),
        ...servers.map((server) {
          return Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
            child: _ServerCard(
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
              onRemove: () {
                if (servers.length == 1) {
                  context.scaffoldMessenger.showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 1),
                      content: Text(context.t.servers.removeLastError),
                    ),
                  );
                  return;
                }
                ref.read(serverStateProvider.notifier).remove(server);
              },
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.router.push(const ServerAddRoute());
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.t.sidebar.addCustomServer),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colorScheme.onSurfaceVariant,
              side: BorderSide(color: context.colorScheme.outlineVariant),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
            ),
          ),
        ),
      ],
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
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

class _ServerCard extends StatelessWidget {
  const _ServerCard({
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
    final nameColor = active ? scheme.onSecondaryContainer : scheme.onSurface;
    final subtitleColor = active
        ? scheme.onSecondaryContainer.withValues(alpha: 0.75)
        : scheme.onSurfaceVariant;
    final uri = server.homepage.toUri();
    final subtitle = uri.host.isNotEmpty ? uri.host : server.homepage;

    return Material(
      color: active
          ? scheme.secondaryContainer
          : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: active
            ? BorderSide(color: scheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingSm,
            vertical: DesignTokens.spacingSm,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: Favicon(
                  url: server.homepage,
                  shape: BoxShape.circle,
                  size: 32,
                  iconSize: 20,
                ),
              ),
              const SizedBox(width: DesignTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.textTheme.bodyMedium?.copyWith(
                        color: nameColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.textTheme.bodySmall?.copyWith(
                          color: subtitleColor,
                        ),
                      ),
                  ],
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
                        const Icon(Icons.edit, size: 18),
                        const SizedBox(width: 8),
                        Text(context.t.edit),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 18),
                        const SizedBox(width: 8),
                        Text(context.t.remove),
                      ],
                    ),
                  ),
                ],
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: active
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
