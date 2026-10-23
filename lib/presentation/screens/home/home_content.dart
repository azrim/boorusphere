import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/provider.dart';
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
    // Aspect-scoped reads: a selection tap or a fetch-status change must not
    // rebuild the screen, and the derived values below stay memoized.
    final data = ref.watch(pageStateProvider.select((it) => it.data));
    final isData = ref.watch(
      pageStateProvider.select((it) => it is DataFetchResult),
    );
    final isLoading = ref.watch(
      pageStateProvider.select((it) => it is LoadingFetchResult),
    );
    final session = ref.watch(searchSessionProvider);
    final servers = ref.watch(serverStateProvider);

    // The blocked set is derived, not selected: a fresh Set per read never
    // compares equal, so select would rebuild on every blocker emission.
    final blockers = ref.watch(tagsBlockerStateProvider);
    final blockedTagsSet = useMemoized(
      () => blockers.values
          .where((it) => it.serverId.isEmpty || it.serverId == session.serverId)
          .map((it) => it.name)
          .toSet(),
      [blockers, session.serverId],
    );

    // Filtering walks every post and allocates a list, so it runs only when
    // the posts or the blocked set change.
    final filteredPosts = useMemoized(
      () => data.posts
          .where((it) => !it.allTags.any(blockedTagsSet.contains))
          .toList(),
      [data.posts, blockedTagsSet],
    );

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

    // One scroll listener for both transient controls: the pagination pill
    // fades while the list is moving, and back-to-top appears once the grid
    // is far enough down to be worth leaving.
    final isScrolling = useState(false);
    final canBackToTop = useState(false);
    useEffect(() {
      Timer? settle;

      void onScroll() {
        final position = scrollController.hasClients
            ? scrollController.position
            : null;
        final canBack = (position?.pixels ?? 0) > 600;
        if (canBack != canBackToTop.value) canBackToTop.value = canBack;

        if (!isScrolling.value) isScrolling.value = true;
        settle?.cancel();
        settle = Timer(const Duration(milliseconds: 700), () {
          isScrolling.value = false;
        });
      }

      scrollController.addListener(onScroll);
      return () {
        scrollController.removeListener(onScroll);
        settle?.cancel();
      };
    }, [scrollController]);

    // React to a successful page change: scroll back to the top and drop any
    // selection that belonged to the previous page.
    final pageIndex = data.pageIndex;
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

    final isNewSearch = !isData && data.option.clear;

    // The bar only needs the count; the selected set is read on demand so a
    // tap does not rebuild the whole screen.
    final hasSelection = ref.watch(
      postSelectionProvider.select((it) => it.isNotEmpty),
    );
    final selectedCount = ref.watch(
      postSelectionProvider.select((it) => it.length),
    );

    final searchBar = ref.watch(searchBarControllerProvider(session));
    final barHeight = useValueListenable(HomeSearchBar.height);

    // The long-press hint is shown once per install. Entering selection mode
    // proves the user found the menu, so that counts as read too.
    final settingsRepo = ref.read(settingsRepoProvider);
    final hintSeen = useState(
      settingsRepo.get(Setting.uiLongPressHintSeen, or: false),
    );
    final showHint =
        !hintSeen.value &&
        !hasSelection &&
        !searchBar.isOpen &&
        data.posts.isNotEmpty;

    useEffect(() {
      if (!hasSelection || hintSeen.value) return null;
      hintSeen.value = true;
      unawaited(settingsRepo.put(Setting.uiLongPressHintSeen, true));
      return null;
    }, [hasSelection]);

    // The hint owns the band above the bar until it is dismissed, so the pill
    // does not compete with it on the first run.
    final showPagination =
        !isNewSearch &&
        data.posts.isNotEmpty &&
        !hasSelection &&
        !searchBar.isOpen &&
        !showHint;

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
        if (!hasSelection) const SearchScreen(),
        // Pagination control
        if (showHint)
          Positioned(
            left: 0,
            right: 0,
            bottom: barHeight + DesignTokens.spacingSm,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingMd,
                ),
                child: _LongPressHint(
                  onDismiss: () {
                    hintSeen.value = true;
                    unawaited(
                      settingsRepo.put(Setting.uiLongPressHintSeen, true),
                    );
                  },
                ),
              ),
            ),
          ),
        if (canBackToTop.value &&
            !hasSelection &&
            !searchBar.isOpen &&
            !showHint)
          Positioned(
            right: DesignTokens.spacingMd,
            bottom: barHeight + DesignTokens.spacingSm,
            child: _BackToTopButton(
              onTap: () => unawaited(
                scrollController.animateTo(
                  0,
                  duration: context.motionDuration(
                    const Duration(milliseconds: 500),
                  ),
                  curve: DesignTokens.curveStandard,
                ),
              ),
            ),
          ),
        if (showPagination)
          Positioned(
            left: 0,
            right: 0,
            bottom: barHeight + DesignTokens.spacingSm,
            child: Center(
              child: AnimatedOpacity(
                // While the grid is moving the pill drops back to a quiet
                // hint instead of asking for a decision mid-scroll.
                opacity: isScrolling.value ? 0.3 : 1,
                duration: context.motionDuration(DesignTokens.durationFast),
                child: _PaginationPill(
                  pageIndex: data.pageIndex,
                  hasPrev: data.hasPrev,
                  hasNext: data.hasNext,
                  loading: isLoading,
                  onPrev: () => unawaited(
                    ref.read(pageStateProvider.notifier).prevPage(),
                  ),
                  onNext: () => unawaited(
                    ref.read(pageStateProvider.notifier).nextPage(),
                  ),
                ),
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
              selectedCount: selectedCount,
              onDownload: (asArchive) async {
                final selection = ref.read(postSelectionProvider);
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
                // Batch favorite: add selected posts to favorites. Only the
                // ones that were not already saved are undoable, so Undo
                // never removes something the user saved earlier.
                final selection = ref.read(postSelectionProvider);
                final favorites = ref.read(favoritePostStateProvider);
                final selectedPosts = filteredPosts
                    .where((post) => selection.contains(post.id))
                    .toList();
                final added = selectedPosts
                    .where((post) => !favorites.contains(post))
                    .toList();
                for (final post in added) {
                  await ref.read(favoritePostStateProvider.notifier).save(post);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.t.batch.favorited(n: added.length)),
                      action: added.isEmpty
                          ? null
                          : SnackBarAction(
                              label: context.t.undo,
                              onPressed: () {
                                for (final post in added) {
                                  ref
                                      .read(favoritePostStateProvider.notifier)
                                      .remove(post);
                                }
                              },
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

/// One-shot hint that teaches the gesture behind every post action. Shown
/// until the reader dismisses it or enters selection mode, then never again:
/// the app teaches by doing instead of opening with an onboarding screen.
class _LongPressHint extends StatelessWidget {
  const _LongPressHint({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.only(left: DesignTokens.spacingMd),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: DesignTokens.iconInline,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Flexible(
                child: Text(
                  context.t.help.longPressHint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.labelLarge,
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                tooltip: context.t.dismiss,
                iconSize: DesignTokens.iconInline,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating return to the top of the grid, shown only once the reader is deep
/// enough that walking back is a chore.
class _BackToTopButton extends StatelessWidget {
  const _BackToTopButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.surfaceContainerHighest,
      elevation: 2,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        onPressed: onTap,
        tooltip: context.t.backToTop,
        icon: const Icon(Icons.arrow_upward_rounded, size: 20),
      ),
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
