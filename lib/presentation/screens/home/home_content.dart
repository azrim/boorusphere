import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/batch_download_provider.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/post_selection_provider.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/home_status.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search/search_screen.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomeContent extends HookConsumerWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(pageStateProvider);
    final session = ref.watch(searchSessionProvider);
    final servers = ref.watch(serverStateProvider);

    // Optimize blocked tags lookup with Set for O(1) contains check
    final blockedTagsSet = ref.watch(
      tagsBlockerStateProvider.select(
        (state) => state.values
            .where(
              (it) => it.serverId.isEmpty || it.serverId == session.serverId,
            )
            .map((it) => it.name)
            .toSet(), // Convert to Set for faster lookup
      ),
    );

    // Use more efficient filtering with Set lookup
    final filteredPosts = pageState.data.posts
        .where((it) => !it.allTags.any(blockedTagsSet.contains))
        .toList(); // Convert to list once for better performance

    useEffect(() {
      if (servers.isNotEmpty) {
        Future(() {
          ref
              .read(pageStateProvider.notifier)
              .update(
                (option) => option.copyWith(query: session.query, clear: true),
              );
        });
      }
      return null;
    }, [servers.isNotEmpty]);

    final timelineController = ref.watch(timelineControllerProvider);
    final scrollController = timelineController.scrollController;

    // React to a successful page change: scroll back to the top and drop any
    // selection that belonged to the previous page.
    final pageIndex = pageState.data.pageIndex;
    final lastPageIndex = useMemoized(() => <int>[pageIndex]);
    useEffect(() {
      final previous = lastPageIndex[0];
      lastPageIndex[0] = pageIndex;
      if (previous == pageIndex) return null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) scrollController.jumpTo(0);
      });
      ref.read(postSelectionProvider.notifier).clear();
      return null;
    }, [pageIndex, scrollController]);

    final isNewSearch =
        pageState is! DataFetchResult && pageState.data.option.clear;

    // Watch selection state for bottom action bar
    final selection = ref.watch(postSelectionProvider);
    final hasSelection = selection.isNotEmpty;

    final searchBar = ref.watch(searchBarControllerProvider(session));
    final barHeight = useValueListenable(HomeSearchBar.height);
    final showPagination =
        !isNewSearch &&
        pageState.data.posts.isNotEmpty &&
        !hasSelection &&
        !searchBar.isOpen;

    if (servers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore,
                size: 72,
                color: context.colorScheme.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              Text(
                context.t.onboarding.welcomeTitle,
                style: context.theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              Text(
                context.t.onboarding.welcomeDesc,
                textAlign: TextAlign.center,
                style: context.theme.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              FilledButton.icon(
                onPressed: () => context.router.push(const ServerAddRoute()),
                icon: const Icon(Icons.add),
                label: Text(context.t.onboarding.addFirstServer),
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              TextButton(
                onPressed: () => context.router.push(ServerPresetRoute()),
                child: Text(context.t.onboarding.browsePresets),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        RefreshIndicator(
          onRefresh: ref.read(pageStateProvider.notifier).load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: scrollController,
            slivers: [
              if (!isNewSearch)
                SliverSafeArea(
                  sliver: SliverPadding(
                    padding: const EdgeInsets.all(DesignTokens.spacingMd),
                    sliver: Timeline(posts: filteredPosts),
                  ),
                ),
              if (!isNewSearch)
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: barHeight + DesignTokens.spacingLg,
                  ),
                  sliver: const SliverToBoxAdapter(child: HomeStatus()),
                )
              else
                const SliverFillRemaining(child: HomeStatus()),
            ],
          ),
        ),
        const _EdgeShadow(),
        // Selection mode owns the bottom of the screen; the bar would only be
        // covered by the action bar while staying reachable for TalkBack.
        if (!hasSelection) SearchScreen(scrollController: scrollController),
        // Pagination control
        if (showPagination)
          Positioned(
            left: 0,
            right: 0,
            bottom: barHeight + DesignTokens.spacingSm,
            child: Center(
              child: _PaginationPill(
                pageIndex: pageState.data.pageIndex,
                hasPrev: pageState.data.hasPrev,
                hasNext: pageState.data.hasNext,
                loading: pageState is LoadingFetchResult,
                onPrev: () =>
                    unawaited(ref.read(pageStateProvider.notifier).prevPage()),
                onNext: () =>
                    unawaited(ref.read(pageStateProvider.notifier).nextPage()),
              ),
            ),
          ),
        // Selection action bar
        if (hasSelection)
          Positioned(
            bottom:
                MediaQuery.viewPaddingOf(context).bottom +
                DesignTokens.spacingMd,
            left: DesignTokens.spacingMd,
            right: DesignTokens.spacingMd,
            child: _SelectionActionBar(
              selectedCount: selection.length,
              onDownload: (asArchive) async {
                final selectedPosts = filteredPosts
                    .where((post) => selection.contains(post.id))
                    .toList();

                if (selectedPosts.isEmpty) return;

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.t.batch.downloading(n: selectedPosts.length),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }

                final imageUrls = selectedPosts
                    .map(
                      (post) => post.sampleFile.isNotEmpty
                          ? post.sampleFile
                          : post.originalFile,
                    )
                    .where((url) => url.isNotEmpty)
                    .toList();

                final result = await BatchDownloadProvider.download(
                  imageUrls,
                  asArchive: asArchive,
                );

                if (context.mounted) {
                  if (result.success) {
                    final msg = asArchive
                        ? context.t.batch.downloaded(
                            n: selectedPosts.length,
                            filename:
                                result.savedPath?.split('/').last ??
                                'batch.zip',
                          )
                        : context.t.batch.downloadedFiles(
                            n: selectedPosts.length,
                          );
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(msg)));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t.batch.failed)),
                    );
                  }
                }
              },
              onFavorite: () async {
                // Batch favorite: add selected posts to favorites
                final selectedPosts = filteredPosts
                    .where((post) => selection.contains(post.id))
                    .toList();
                for (final post in selectedPosts) {
                  await ref.read(favoritePostStateProvider.notifier).save(post);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.t.batch.favorited(n: selectedPosts.length),
                      ),
                    ),
                  );
                }
                ref.read(postSelectionProvider.notifier).clear();
              },
              onClear: () {
                ref.read(postSelectionProvider.notifier).clear();
              },
            ),
          ),
      ],
    );
  }
}

/// Contextual bar shown while posts are selected. The count is a readout, not
/// a button label, and the archive option is a menu choice instead of a
/// switch-shaped icon, so each control names the action it performs.
class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.selectedCount,
    required this.onDownload,
    required this.onFavorite,
    required this.onClear,
  });

  final int selectedCount;
  final void Function(bool asArchive) onDownload;
  final VoidCallback onFavorite;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingSm,
              ),
              child: Text(
                '$selectedCount',
                style: context.theme.textTheme.titleMedium,
                semanticsLabel: context.t.batch.selected(n: selectedCount),
              ),
            ),
            const Spacer(),
            PopupMenuButton<bool>(
              tooltip: context.t.downloads.title,
              icon: const Icon(Icons.download_rounded),
              onSelected: onDownload,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: false,
                  child: Row(
                    children: [
                      const Icon(Icons.download_outlined),
                      const SizedBox(width: DesignTokens.spacingMd),
                      Flexible(child: Text(context.t.batch.downloadFiles)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: true,
                  child: Row(
                    children: [
                      const Icon(Icons.folder_zip_outlined),
                      const SizedBox(width: DesignTokens.spacingMd),
                      Flexible(child: Text(context.t.batch.asArchive)),
                    ],
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: onFavorite,
              tooltip: context.t.favorites.title,
              icon: const Icon(Icons.favorite_border),
            ),
            IconButton(
              onPressed: onClear,
              tooltip: context.t.clearSelection,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _EdgeShadow extends StatelessWidget {
  const _EdgeShadow();

  @override
  Widget build(BuildContext context) {
    final tint = context.theme.scaffoldBackgroundColor;
    final paddingTop = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: SizedBox(
            height: paddingTop * 1.8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomLeft,
                  colors: [
                    tint.withValues(alpha: 0.8),
                    tint.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact floating pagination control: previous arrow, page indicator and
/// next arrow. Displayed above the bottom search bar.
class _PaginationPill extends StatelessWidget {
  const _PaginationPill({
    required this.pageIndex,
    required this.hasPrev,
    required this.hasNext,
    required this.loading,
    required this.onPrev,
    required this.onNext,
  });

  final int pageIndex;
  final bool hasPrev;
  final bool hasNext;
  final bool loading;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.surfaceContainerHighest,
      elevation: 2,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: hasPrev && !loading ? onPrev : null,
              tooltip: context.t.pagination.previous,
              iconSize: 20,
              icon: const Icon(Icons.chevron_left),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64),
              child: Center(
                child: loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        context.t.pagination.page(page: pageIndex),
                        style: context.theme.textTheme.labelLarge,
                      ),
              ),
            ),
            IconButton(
              onPressed: hasNext && !loading ? onNext : null,
              tooltip: context.t.pagination.next,
              iconSize: 20,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
