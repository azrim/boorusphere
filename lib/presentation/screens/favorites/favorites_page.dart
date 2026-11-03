import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/empty_state.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// One server's favorites, as one tab of the page.
typedef FavoriteTab = ({Server server, List<Post> posts});

/// Groups [posts] into one tab per server, dropping the ones whose server is
/// gone: a post id only means something with the booru that assigned it.
///
/// The page decides its empty state from the result, not from the record
/// count: favorites left behind by a deleted server cannot be shown, opened or
/// removed, so a list made only of them has nothing to page through.
@visibleForTesting
List<FavoriteTab> favoriteTabsOf(
  Iterable<Post> posts,
  Iterable<Server> servers,
) {
  return posts
      .groupListsBy((e) => servers.getById(e.serverId, or: Server.empty))
      .entries
      .where((it) => it.key != Server.empty)
      .sortedBy((it) => it.key.id)
      .map((it) => (server: it.key, posts: it.value))
      .toList();
}

@RoutePage()
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key, this.session});
  final SearchSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritePostState = ref.watch(favoritePostStateProvider);
    final tabs = favoriteTabsOf(
      favoritePostState,
      ref.watch(serverStateProvider),
    );
    final savedServerId = ref.read(
      serverSettingStateProvider.select((it) => it.lastActiveId),
    );
    final session = this.session ?? SearchSession(serverId: savedServerId);

    return ProviderScope(
      overrides: [searchSessionProvider.overrideWith((ref) => session)],
      child: tabs.isEmpty ? const _EmptyView() : _Pager(tabs),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.favorites.title)),
      body: SafeArea(
        child: EmptyState(
          icon: const Icon(Icons.favorite),
          title: context.t.favorites.placeholder,
          body: context.t.favoritesHint,
          // The only way to fill this list is the feed behind the page.
          action: FilledButton(
            onPressed: () => context.navigator.maybePop(),
            child: Text(context.t.browseFeed),
          ),
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager(this.tabs);

  final List<FavoriteTab> tabs;

  @override
  Widget build(BuildContext context) {
    final flat = AppSurfacePolicy.of(context).flat;
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        extendBody: true,
        appBar: AppBar(title: Text(context.t.favorites.title)),
        body: TabBarView(
          children: [
            for (final tab in tabs)
              _Content(server: tab.server, posts: tab.posts),
          ],
        ),
        bottomNavigationBar: Material(
          // The strip floats over the grid in the lifted themes, but Midnight
          // keeps every surface on the page: black, no elevation, a hairline
          // for the edge. Asking the policy is what keeps it off black as a
          // grey slab with a shadow.
          color: flat
              ? context.colorScheme.surface
              : context.colorScheme.surfaceContainer,
          surfaceTintColor: context.colorScheme.surfaceTint,
          elevation: flat ? 0 : DesignTokens.elevationFloating,
          shadowColor: flat
              ? Colors.transparent
              : DesignTokens.shadowColor(context.colorScheme),
          child: SafeArea(
            child: TabBar(
              dividerColor: Colors.transparent,
              labelStyle: context.theme.textTheme.labelMedium,
              padding: const EdgeInsets.all(DesignTokens.spacingSm),
              isScrollable: true,
              labelPadding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingSm,
              ),
              splashFactory: InkSparkle.splashFactory,
              tabs: [
                for (final tab in tabs)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingSm,
                    ),
                    child: Tab(
                      text: tab.server.name,
                      icon: Favicon(
                        url: tab.server.homepage,
                        size: 16,
                        shape: BoxShape.rectangle,
                      ),
                    ),
                  ),
              ],
              indicator: BoxDecoration(
                color: context.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.posts, required this.server});

  final Iterable<Post> posts;
  final Server server;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        // One controller per tab. A controller shared by every tab shares its
        // tag map too: a neighbouring tab built during a cancelled swipe would
        // overwrite the visible tab's indices, and the viewer could no longer
        // scroll the feed it was opened from.
        timelineControllerProvider.overrideWith(
          (ref) => TimelineController(scrollController: AutoScrollController()),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final timelineController = ref.watch(timelineControllerProvider);

          return CustomScrollView(
            controller: timelineController.scrollController,
            slivers: [
              SliverSafeArea(
                sliver: SliverPadding(
                  padding: const EdgeInsets.all(DesignTokens.spacingMd),
                  // No batch action bar here, so selection would be a dead
                  // end.
                  sliver: Timeline(posts: posts, enableSelection: false),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
