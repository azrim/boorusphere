import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_updater.dart';
import 'package:boorusphere/presentation/provider/app_versions/app_versions_state.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomeDrawer extends StatelessWidget {
  const HomeDrawer({super.key, required this.maxWidth});

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: maxWidth,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(DesignTokens.radiusXl),
          bottomRight: Radius.circular(DesignTokens.radiusXl),
        ),
      ),
      child: SafeArea(
        child: ListTileTheme(
          data: context.theme.listTileTheme.copyWith(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingLg),
          ),
          child: const Column(
            children: [
              _Header(),
              Expanded(child: _ServerSelection()),
              _Footer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _HomeTile(),
        ListTile(
          title: Text(context.t.downloads.title),
          leading: const Icon(Icons.cloud_download),
          onTap: () => context.router.push(DownloadsRoute(session: session)),
        ),
        ListTile(
          title: Text(context.t.favorites.title),
          leading: const Icon(Icons.favorite_border),
          onTap: () => context.router.push(FavoritesRoute(session: session)),
        ),
        ListTile(
          title: Text(context.t.tagsBlocker.title),
          leading: const Icon(Icons.block),
          onTap: () => context.router.push(const TagsBlockerRoute()),
        ),
        ListTile(
          title: Text(context.t.settings.title),
          leading: const Icon(Icons.settings),
          onTap: () => context.router.push(const SettingsRoute()),
        ),
        ListTile(
          title: Text(context.t.exit),
          leading: const Icon(Icons.exit_to_app),
          onTap: () => _showExitDialog(context),
        ),
        const AppVersionTile(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingXl, DesignTokens.spacingMd, DesignTokens.spacingMd),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Boorusphere!', style: context.theme.textTheme.headlineMedium),
          _ThemeSwitcherButton(),
        ],
      ),
    );
  }
}

class _ThemeSwitcherButton extends ConsumerWidget {
  IconData themeIconOf(ThemeMode mode) {
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
    final theme = ref.watch(
      uiSettingStateProvider.select((ui) => ui.themeMode),
    );

    return IconButton(
      icon: Icon(themeIconOf(theme)),
      onPressed: () =>
          ref.read(uiSettingStateProvider.notifier).cycleThemeMode(),
    );
  }
}

class AppVersionTile extends ConsumerWidget {
  const AppVersionTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appVersions = ref.watch(appVersionsStateProvider);
    final updateProgress = ref.watch(appUpdateProgressProvider);

    final currentTile = ListTile(
      title: appVersions.maybeWhen(
        data: (data) => Text('Boorusphere ${data.current}'),
        orElse: () => const Text('Boorusphere'),
      ),
      leading: const Icon(Icons.info_outline),
      onTap: () => context.router.push(const AboutRoute()),
    );

    return appVersions.maybeWhen(
      data: (data) {
        if (!data.latest.isNewerThan(data.current)) return currentTile;
        if (updateProgress.status.isDownloading) {
          return ListTile(
            title: Text(context.t.updater.available(version: '${data.latest}')),
            leading: const SizedBox(
              height: 24,
              width: 24,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
            subtitle: Text(
              context.t.updater.progress(progress: updateProgress.progress),
            ),
            onTap: () => context.router.push(const AboutRoute()),
          );
        }
        return ListTile(
          title: Text(context.t.updater.available(version: '${data.latest}')),
          leading: Icon(Icons.info_outline, color: Colors.pink.shade300),
          subtitle: Text(
            updateProgress.status.isDownloaded
                ? context.t.updater.install
                : context.t.changelog.view,
          ),
          onTap: () {
            context.router.push(const AboutRoute());
          },
        );
      },
      orElse: () => currentTile,
    );
  }
}

class _HomeTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SizedBox.shrink(); // Always hidden - users can clear search instead
  }
}

class _ServerSelection extends ConsumerWidget {
  const _ServerSelection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverStateProvider);
    final session = ref.watch(searchSessionProvider);
    final serverActive = servers.getById(session.serverId);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ...servers.map((it) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, DesignTokens.spacingMd, 0),
            child: ListTile(
              title: Text(it.name),
              leading: Favicon(
                url: it.homepage,
                shape: BoxShape.circle,
                iconSize: 21,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      Navigator.of(context).pop();
                      context.router.push(ServerEditorRoute(server: it));
                      break;
                    case 'remove':
                      if (servers.length == 1) {
                        context.scaffoldMessenger.showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 1),
                            content: Text(context.t.servers.removeLastError),
                          ),
                        );
                        break;
                      }
                      ref.read(serverStateProvider.notifier).remove(it);
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
                icon: const Icon(Icons.more_vert, size: 18),
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(DesignTokens.radiusXl),
                  bottomRight: Radius.circular(DesignTokens.radiusXl),
                ),
              ),
              selected: it.id == serverActive.id,
              selectedTileColor: context.colorScheme.primary.withAlpha(
                context.isLightThemed ? 50 : 25,
              ),
              onTap: () {
                Navigator.of(context).pop();
                if (it.id != serverActive.id) {
                  context.router.push(
                    HomeRoute(session: session.copyWith(serverId: it.id)),
                  );
                } else {
                  ref
                      .read(pageStateProvider.notifier)
                      .update((it) => it.copyWith(clear: true));
                }
              },
            ),
          );
        }),
        // Add New Server button
        Padding(
          padding: const EdgeInsets.fromLTRB(0, DesignTokens.spacingSm, DesignTokens.spacingMd, 0),
          child: ListTile(
            title: Text(context.t.servers.add),
            leading: const Icon(Icons.add_circle_outline, size: 21),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            onTap: () => context.router.push(const ServerAddRoute()),
          ),
        ),
        // Reset servers button
        Padding(
          padding: const EdgeInsets.fromLTRB(0, DesignTokens.spacingXs, DesignTokens.spacingMd, 0),
          child: ListTile(
            title: Text(context.t.resetToDefault),
            leading: const Icon(Icons.restore, size: 21),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(context.t.resetToDefault),
                  icon: const Icon(Icons.restore),
                  content: Text(context.t.servers.resetWarning),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(context.t.cancel),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        ref.read(serverStateProvider.notifier).reset();
                      },
                      child: Text(context.t.reset),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

void _showExitDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
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
      );
    },
  );
}
