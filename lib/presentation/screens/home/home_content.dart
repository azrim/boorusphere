import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/data/repository/tags_blocker/tag_expression.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/batch_download_provider.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/entity/page_data.dart';
import 'package:boorusphere/presentation/provider/booru/feed_filter_state.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/post_selection_provider.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/download_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/first_run_view.dart';
import 'package:boorusphere/presentation/screens/home/home_status.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search/search_screen.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:flutter/foundation.dart';
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
    final feedMode = ref.watch(
      uiSettingStateProvider.select((it) => it.feedMode),
    );
    // Only the filters themselves, not the whole setting: the notice below and
    // its way out depend on whether a local filter is the one hiding the page.
    final filtering = ref.watch(
      contentSettingStateProvider.select(
        (it) => it.hideFavorited || it.hideDownloaded,
      ),
    );

    // The blocked set is derived, not selected: a fresh list per read never
    // compares equal, so select would rebuild on every blocker emission.
    final blockers = ref.watch(tagsBlockerStateProvider);
    final blockedExpressions = useMemoized(
      () => parseBlockedTagExpressions(
        blockers.values
            .where(
              (it) => it.serverId.isEmpty || it.serverId == session.serverId,
            )
            .map((it) => it.name),
      ),
      [blockers, session.serverId],
    );

    // Filtering walks every post and allocates a list, so it runs only when
    // the posts or the blocked set change. The local filters are derived as one
    // set for the same reason: a favorite added from the grid hides its post
    // without a refetch.
    final hidden = ref.watch(hiddenFeedPostKeysProvider);
    final filteredPosts = useMemoized(
      () => data.posts
          .where(
            (it) =>
                !matchesBlockedTagExpressions(blockedExpressions, it.allTags) &&
                !hidden.contains(feedPostKeyOf(it)),
          )
          .toList(),
      [data.posts, blockedExpressions, hidden],
    );

    // The selection only names posts the grid still shows. Blocking a tag,
    // turning on a local filter or a reload that landed other results can take
    // a selected post away; the bar would keep counting it while the batch
    // handler silently skipped it. Written after the frame, like the reset
    // below, because the provider cannot be touched during build.
    final visibleIds = useMemoized(
      () => {for (final post in filteredPosts) post.id},
      [filteredPosts],
    );
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(postSelectionProvider.notifier).retainAll(visibleIds);
      });
      return null;
    }, [visibleIds]);

    // Hiding is applied while rendering, but a page skipped because every one
    // of its entries was hidden never arrived, and an all-hidden first page is
    // reported as an error. Turning a filter off has to ask for the page again
    // for those to come back; the page-state guards fold the request into an
    // in-flight fetch.
    ref.listen(
      contentSettingStateProvider.select(
        (it) => (it.hideFavorited, it.hideDownloaded),
      ),
      (previous, next) {
        if (previous == next) return;
        unawaited(ref.read(pageStateProvider.notifier).load());
      },
    );

    // The page size and the rating are part of the result window: the same
    // page index addresses other posts once either moves, and the posts on
    // screen were fetched under the old window. Watch the pair where the feed
    // lives instead of reloading from each writer: a rating picked from the
    // chip and a limit picked on the settings page both have to reach every
    // feed still open behind them.
    ref.listen(
      serverSettingStateProvider.select(
        (it) => (it.searchRating, it.postLimit),
      ),
      (previous, next) {
        if (previous == next) return;
        unawaited(ref.read(pageStateProvider.notifier).load());
      },
    );

    // The blockers are applied when a page is fetched, so a tag blocked or
    // unblocked later cannot re-shape the posts already on screen: the pages
    // it removed never arrived. Ask for the page again when the set that
    // applies to this server changes; the page state folds the request into a
    // fetch already in flight.
    ref.listen(tagsBlockerStateProvider, (previous, next) {
      final before = _blockedNamesFor(previous ?? const {}, session.serverId);
      final after = _blockedNamesFor(next, session.serverId);
      if (listEquals(before, after)) return;
      unawaited(ref.read(pageStateProvider.notifier).load());
    });

    // A mode change re-indexes what is on screen: paged lands on the last page
    // the reader left, infinite holds a list that has no page. Restart the
    // result set so neither mode inherits the other's cursor.
    ref.listen(uiSettingStateProvider.select((it) => it.feedMode), (
      previous,
      next,
    ) {
      if (previous == next) return;
      unawaited(
        ref
            .read(pageStateProvider.notifier)
            .update((option) => option.copyWith(clear: true)),
      );
    });

    // A failed step or refresh keeps the posts already on screen, so the status
    // card that explains it is appended below the whole page and never seen.
    // Answer the action where it was taken instead; the retry path is the one
    // the reader already knows.
    ref.listen(pageStateProvider, (previous, next) {
      if (next is! ErrorFetchResult<PageData>) return;
      if (next.data.posts.isEmpty) return;
      // A retry that fails the same way is a new answer, not a repeat of the
      // one already on screen; only an unchanged error is skipped.
      if (previous is ErrorFetchResult<PageData> &&
          previous.error == next.error) {
        return;
      }
      final server = servers.getById(session.serverId);
      showToast(
        context,
        describePageStatus(context, next.data, next.error, server),
      );
    });

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

    // What the grid actually shows: a page can arrive full and be emptied by
    // the local filters or the tags blocker, and every piece of chrome below
    // has to describe the grid's state rather than the response's.
    final hasVisiblePosts = filteredPosts.isNotEmpty;

    final timelineController = ref.watch(timelineControllerProvider);
    final scrollController = timelineController.scrollController;

    // One scroll listener for both transient controls: the pagination pill
    // fades while the list is moving, and back-to-top appears once the grid
    // is far enough down to be worth leaving. Both live in notifiers so a
    // scroll tick repaints the two controls, not the grid between them.
    final isScrolling = useMemoized(() => ValueNotifier(false));
    final canBackToTop = useMemoized(() => ValueNotifier(false));
    useEffect(() {
      return () {
        isScrolling.dispose();
        canBackToTop.dispose();
      };
    }, const []);
    useEffect(() {
      Timer? settle;

      void onScroll() {
        final position = scrollController.hasClients
            ? scrollController.position
            : null;
        final canBack = (position?.pixels ?? 0) > 600;
        if (canBack != canBackToTop.value) canBackToTop.value = canBack;

        // Infinite mode grows the list as the end comes into view. The guards
        // live in PageState; reading the freshest state here keeps a tick from
        // asking for a page already on the wire or past the end.
        if (feedMode == FeedMode.infinite &&
            position != null &&
            position.extentAfter < 600) {
          final result = ref.read(pageStateProvider);
          if (result is DataFetchResult) {
            final data = result.data;
            if (data.hasNext && data.posts.isNotEmpty && !data.limitReached) {
              unawaited(ref.read(pageStateProvider.notifier).loadMore());
            }
          }
        }

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
    }, [scrollController, feedMode]);

    // React to a page change or a new query: scroll back to the top and drop
    // any selection that belonged to the previous results.
    final pageIndex = data.pageIndex;
    final query = data.option.query;
    final restartSerial = data.restartSerial;
    final lastPageIndex = useMemoized(() => <int>[pageIndex]);
    final lastQuery = useMemoized(() => <String>[query]);
    final lastFeedMode = useMemoized(() => <FeedMode>[feedMode]);
    final lastRestartSerial = useMemoized(() => <int>[restartSerial]);
    useEffect(() {
      final indexChanged = lastPageIndex[0] != pageIndex;
      lastPageIndex[0] = pageIndex;
      // A new query restarts at the first page, so the index alone does not
      // change and the new results would open at the old offset.
      final queryChanged = lastQuery[0] != query;
      lastQuery[0] = query;
      final modeChanged = lastFeedMode[0] != feedMode;
      lastFeedMode[0] = feedMode;
      // A reload that starts the result set over (a rating or filter change,
      // a refresh) also has to move the viewport back. Its page index is not
      // enough to tell it from an append, which must leave the reader where
      // they are, so the page state counts restarts separately.
      final resetChanged = lastRestartSerial[0] != restartSerial;
      lastRestartSerial[0] = restartSerial;
      // Appending in infinite mode moves the page index, but it must not yank
      // the reader back to the top; only a paged step, a restart, a new query
      // or a mode switch opens at the first result.
      final restart =
          resetChanged ||
          queryChanged ||
          modeChanged ||
          (indexChanged && feedMode == FeedMode.paged);
      if (!restart) return null;

      // Effects run while the tree is still building, so both the scroll jump
      // and the selection reset have to wait for the frame to finish.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (scrollController.hasClients) scrollController.jumpTo(0);
        ref.read(postSelectionProvider.notifier).clear();
      });
      return null;
    }, [pageIndex, query, feedMode, restartSerial, scrollController]);

    final isNewSearch = !isData && data.option.clear;

    // The bar only needs the count; the selected set is read on demand so a
    // tap does not rebuild the whole screen.
    final hasSelection = ref.watch(
      postSelectionProvider.select((it) => it.isNotEmpty),
    );
    final selectedCount = ref.watch(
      postSelectionProvider.select((it) => it.length),
    );

    // Batch progress lives in a notifier so the action bar repaints on it
    // without rebuilding the grid behind it.
    final downloadProgress = useMemoized(
      () => ValueNotifier<BatchDownloadProgress?>(null),
      const [],
    );
    useEffect(() => downloadProgress.dispose, [downloadProgress]);

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
        hasVisiblePosts;

    useEffect(() {
      if (!hasSelection || hintSeen.value) return null;
      hintSeen.value = true;
      unawaited(settingsRepo.put(Setting.uiLongPressHintSeen, true));
      return null;
    }, [hasSelection]);

    // The hint owns the band above the bar until it is dismissed, so the pill
    // does not compete with it on the first run.
    final showPagination =
        feedMode == FeedMode.paged &&
        !isNewSearch &&
        hasVisiblePosts &&
        !hasSelection &&
        !searchBar.isOpen &&
        !showHint;

    // The response had posts but none survived the local filters or the tags
    // blocker. Loaded data is not the same as visible data, so this state gets
    // its own notice with the control that undoes it, instead of a blank grid
    // under chrome that claims there is something to page through.
    final allHidden = data.posts.isNotEmpty && !hasVisiblePosts;

    if (servers.isEmpty) return const FirstRunView();

    return Stack(
      alignment: Alignment.center,
      children: [
        // Under the open search panel the grid is not visible, so it must not
        // be reachable either: TalkBack would read and activate cards the
        // reader cannot see.
        ExcludeSemantics(
          excluding: searchBar.isOpen,
          child: RefreshIndicator(
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
                if (!isNewSearch && feedMode == FeedMode.infinite)
                  SliverToBoxAdapter(
                    child: _InfiniteFooter(
                      loading: isLoading,
                      hasPosts: hasVisiblePosts,
                      hasNext: data.hasNext,
                      limitReached: data.limitReached,
                    ),
                  ),
                if (!isNewSearch)
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: barHeight + DesignTokens.spacingLg,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: allHidden
                          ? _NothingVisible(
                              filtering: filtering,
                              onShowAll: () {
                                final settings = ref.read(
                                  contentSettingStateProvider.notifier,
                                );
                                unawaited(settings.setHideFavorited(false));
                                unawaited(settings.setHideDownloaded(false));
                              },
                              onManageBlocked: () => unawaited(
                                context.router.push(const TagsBlockerRoute()),
                              ),
                            )
                          // One operation, one progress signal: a step with the
                          // grid on screen is already reported by the paging
                          // pill, so only a load with nothing to show gets the
                          // placeholder grid.
                          : HomeStatus(skeletonWhenLoading: data.posts.isEmpty),
                    ),
                  )
                else
                  const SliverFillRemaining(child: HomeStatus()),
              ],
            ),
          ),
        ),
        const _EdgeShadow(),
        // Selection mode owns the bottom of the screen: the bar would only be
        // covered by the action bar while staying reachable for TalkBack. The
        // swap is a handover, not a cut, because the action bar takes exactly
        // the place the bar held.
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: context.motionDuration(DesignTokens.durationFast),
            transitionBuilder: _handoverTransition,
            child: hasSelection
                ? const SizedBox.shrink(key: ValueKey('search-hidden'))
                : const SearchScreen(key: ValueKey('search')),
          ),
        ),
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
        if (!hasSelection && !searchBar.isOpen && !showHint)
          ValueListenableBuilder<bool>(
            valueListenable: canBackToTop,
            builder: (context, canBack, child) {
              final duration = context.motionDuration(
                DesignTokens.durationFast,
              );
              // Kept mounted while hidden so leaving the deep end of the grid
              // fades the button out instead of cutting it. The animation is
              // the only thing that changes; the button itself is `child`.
              return Positioned(
                right: DesignTokens.spacingMd,
                bottom: barHeight + DesignTokens.spacingSm,
                child: ExcludeSemantics(
                  excluding: !canBack,
                  child: IgnorePointer(
                    ignoring: !canBack,
                    child: AnimatedOpacity(
                      opacity: canBack ? 1 : 0,
                      duration: duration,
                      child: AnimatedSlide(
                        offset: canBack ? Offset.zero : const Offset(0, 0.15),
                        duration: duration,
                        curve: DesignTokens.curveStandard,
                        child: child,
                      ),
                    ),
                  ),
                ),
              );
            },
            child: _BackToTopButton(
              onTap: () => unawaited(
                scrollController.animateTo(
                  0,
                  duration: context.motionDuration(DesignTokens.durationSlow),
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
              child: ValueListenableBuilder<bool>(
                valueListenable: isScrolling,
                builder: (context, scrolling, child) => AnimatedOpacity(
                  // While the grid is moving the pill drops back to a quiet
                  // hint instead of asking for a decision mid-scroll.
                  opacity: scrolling ? 0.3 : 1,
                  duration: context.motionDuration(DesignTokens.durationFast),
                  child: child,
                ),
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
        Positioned(
          bottom:
              MediaQuery.viewPaddingOf(context).bottom + DesignTokens.spacingMd,
          left: DesignTokens.spacingMd,
          right: DesignTokens.spacingMd,
          child: AnimatedSwitcher(
            duration: context.motionDuration(DesignTokens.durationFast),
            transitionBuilder: _handoverTransition,
            child: hasSelection
                ? _SelectionActionBar(
                    key: const ValueKey('selection'),
                    selectedCount: selectedCount,
                    progress: downloadProgress,
                    onDownload: () async {
                      final selection = ref.read(postSelectionProvider);
                      final selectedPosts = filteredPosts
                          .where((post) => selection.contains(post.id))
                          .toList();

                      if (selectedPosts.isEmpty) return;

                      // The batch saves what the quality setting asks for, the same
                      // way the single-file picker does.
                      final quality = ref
                          .read(downloadSettingStateProvider)
                          .quality;
                      final imageUrls = selectedPosts
                          .map((post) => batchSourceUrlOf(post, quality))
                          .where((url) => url.isNotEmpty)
                          .toList();

                      // The bar carries the status: it counts the settled files and
                      // moves its own progress line while the batch runs.
                      if (imageUrls.isNotEmpty) {
                        downloadProgress.value = (
                          done: 0,
                          total: imageUrls.length,
                          fraction: 0,
                        );
                      }

                      final BatchDownloadResult result;
                      try {
                        result = await BatchDownloadProvider.download(
                          imageUrls,
                          storage: ref.read(sharedStorageHandleProvider),
                          ref: ref,
                          posts: selectedPosts,
                          // The batch outlives this page when the reader leaves, so
                          // both writes check that the notifier still has an owner
                          // before touching it.
                          onProgress: (progress) {
                            if (context.mounted) {
                              downloadProgress.value = progress;
                            }
                          },
                        );
                      } finally {
                        if (context.mounted) downloadProgress.value = null;
                      }

                      if (context.mounted) {
                        if (result.success) {
                          // The count comes from the batch, not from the request:
                          // a URL that answered with something other than media was
                          // dropped, and the message reports what reached the disk.
                          showToast(
                            context,
                            context.t.batch.downloadedFiles(
                              n: result.savedCount,
                            ),
                          );
                        } else {
                          showToast(context, context.t.batch.failed);
                        }
                      }
                    },
                    onFavorite: () async {
                      // Batch favorite: add selected posts to favorites. Only the
                      // ones that were not already saved are undoable, so Undo
                      // never removes something the user saved earlier.
                      final selection = ref.read(postSelectionProvider);
                      final favorites = ref.read(
                        favoritePostStateProvider.notifier,
                      );
                      final selectedPosts = filteredPosts
                          .where((post) => selection.contains(post.id))
                          .toList();
                      final added = selectedPosts
                          .where((post) => !favorites.isFavorite(post))
                          .toList();
                      for (final post in added) {
                        await favorites.save(post);
                      }
                      if (context.mounted) {
                        showToast(
                          context,
                          context.t.batch.favorited(n: added.length),
                          // The batch is one action, so its undo gets the same
                          // bounded window as every other destructive result. The
                          // toast outlives this page, but not the moment it
                          // belongs to.
                          duration: added.isEmpty
                              ? DesignTokens.durationSnackbar
                              : DesignTokens.durationUndo,
                          actionLabel: added.isEmpty ? null : context.t.undo,
                          // The toast lives in the root messenger, so it survives
                          // this page being popped. Undo therefore has to use the
                          // keepAlive notifier captured above instead of this
                          // widget's ref, which is disposed with the page.
                          onAction: added.isEmpty
                              ? null
                              : () {
                                  for (final post in added) {
                                    favorites.remove(post);
                                  }
                                },
                        );
                      }
                      if (context.mounted) {
                        ref.read(postSelectionProvider.notifier).clear();
                      }
                    },
                    onClear: () {
                      ref.read(postSelectionProvider.notifier).clear();
                    },
                  )
                : const SizedBox.shrink(key: ValueKey('selection-hidden')),
          ),
        ),
      ],
    );
  }
}

/// Tag names blocked on [serverId], sorted so two blocker maps that differ
/// only in order compare equal.
List<String> _blockedNamesFor(Map<int, BooruTag> blockers, String serverId) {
  return [
    for (final entry in blockers.values)
      if (entry.serverId.isEmpty || entry.serverId == serverId) entry.name,
  ]..sort();
}

/// Fades a child while lifting it the last [DesignTokens.spacingSm] into
/// place, for chrome that replaces other chrome at the same edge. Under
/// reduced motion the duration is zero, so the swap is a cut.
Widget _handoverTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, inner) => Transform.translate(
        offset: Offset(0, (1 - animation.value) * DesignTokens.spacingSm),
        child: inner,
      ),
      child: child,
    ),
  );
}

/// The page arrived full and every post on it is hidden by the local filters or
/// by the tags blocker. Names the state and offers the one control that can
/// bring the posts back, instead of an empty grid under paging chrome.
class _NothingVisible extends StatelessWidget {
  const _NothingVisible({
    required this.filtering,
    required this.onShowAll,
    required this.onManageBlocked,
  });

  /// Whether a local content filter is hiding posts. When it is not, the tags
  /// blocker is the one that is, and the way out is its own screen.
  final bool filtering;

  final VoidCallback onShowAll;
  final VoidCallback onManageBlocked;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: NoticeCard(
        icon: const Icon(Icons.filter_alt_off_outlined),
        margin: const EdgeInsets.all(DesignTokens.spacingMd),
        children: Column(
          children: [
            Text(
              filtering
                  ? context.t.pageStatus.filteredEmpty
                  : context.t.pageStatus.blockedEmpty,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            FilledButton(
              onPressed: filtering ? onShowAll : onManageBlocked,
              child: Text(
                filtering
                    ? context.t.pageStatus.showAll
                    : context.t.tagsBlocker.title,
              ),
            ),
          ],
        ),
      ),
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
    final flat = AppSurfacePolicy.of(context).flat;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
          side: flat
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
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

/// Inline status at the end of an infinite feed: the append spinner, the end
/// of the results, or the in-memory ceiling that asks for a restart.
class _InfiniteFooter extends StatelessWidget {
  const _InfiniteFooter({
    required this.loading,
    required this.hasPosts,
    required this.hasNext,
    required this.limitReached,
  });

  final bool loading;
  final bool hasPosts;
  final bool hasNext;
  final bool limitReached;

  @override
  Widget build(BuildContext context) {
    if (!hasPosts) return const SizedBox.shrink();

    final Widget? child;
    if (limitReached) {
      child = Text(
        context.t.feed.limitReached,
        textAlign: TextAlign.center,
        style: AppTextRoles.of(context).rowSupporting,
      );
    } else if (loading) {
      child = const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (!hasNext) {
      child = Text(
        context.t.feed.endOfResults,
        textAlign: TextAlign.center,
        style: AppTextRoles.of(context).rowSupporting,
      );
    } else {
      child = null;
    }
    if (child == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingMd,
      ),
      child: Center(child: child),
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
      color: context.colorScheme.surfaceContainerHigh,
      elevation: DesignTokens.elevationFloating,
      shadowColor: DesignTokens.shadowColor(context.colorScheme),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        onPressed: onTap,
        tooltip: context.t.backToTop,
        icon: const Icon(
          Icons.arrow_upward_rounded,
          size: DesignTokens.iconAction,
        ),
      ),
    );
  }
}

/// Contextual bar shown while posts are selected. The count is a readout, not
/// a button label, and every control does exactly one thing: the download
/// button saves the selection as files, with no archive mode behind it that
/// would silently carry from one tap to the next.
class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    super.key,
    required this.selectedCount,
    required this.progress,
    required this.onDownload,
    required this.onFavorite,
    required this.onClear,
  });

  final int selectedCount;

  /// Progress of a running batch, null when nothing is downloading. The bar
  /// turns into the status of that batch while it is set, so the actions that
  /// would start another one are disabled.
  final ValueListenable<BatchDownloadProgress?> progress;

  final VoidCallback onDownload;
  final VoidCallback onFavorite;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BatchDownloadProgress?>(
      valueListenable: progress,
      builder: (context, value, _) {
        final colorScheme = context.colorScheme;

        return Card(
          elevation: DesignTokens.elevationFloating,
          shadowColor: DesignTokens.shadowColor(colorScheme),
          color: colorScheme.surfaceContainerHigh,
          // The other floating controls place their own inset, so the bar must
          // not pick up the Card's default margin on top of it.
          margin: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingXs,
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacingSm,
                      ),
                      child: Text(
                        value == null
                            ? '$selectedCount'
                            : '${value.done}/${value.total}',
                        style: context.theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        semanticsLabel: value == null
                            ? context.t.batch.selected(n: selectedCount)
                            : context.t.batch.downloading(n: value.total),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: value == null ? onDownload : null,
                      tooltip: context.t.batch.downloadFiles,
                      icon: value == null
                          ? const Icon(Icons.download_rounded)
                          : SizedBox.square(
                              dimension: DesignTokens.iconInline,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: value.fraction,
                              ),
                            ),
                    ),
                    IconButton(
                      onPressed: value == null ? onFavorite : null,
                      tooltip: context.t.favorites.title,
                      icon: const Icon(Icons.favorite_border),
                    ),
                    IconButton(
                      onPressed: value == null ? onClear : null,
                      tooltip: context.t.clearSelection,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (value != null)
                LinearProgressIndicator(
                  value: value.fraction,
                  minHeight: DesignTokens.spacingXs,
                  semanticsLabel: context.t.batch.downloading(n: value.total),
                ),
            ],
          ),
        );
      },
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
      color: context.colorScheme.surfaceContainerHigh,
      elevation: DesignTokens.elevationFloating,
      shadowColor: DesignTokens.shadowColor(context.colorScheme),
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
              iconSize: DesignTokens.iconAction,
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
              iconSize: DesignTokens.iconAction,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
