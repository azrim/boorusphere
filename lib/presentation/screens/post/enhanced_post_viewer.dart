import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/routes/slide_page_route.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/screens/post/hooks/precache_posts.dart';
import 'package:boorusphere/presentation/screens/post/post_details_sheet.dart';
import 'package:boorusphere/presentation/screens/post/post_image.dart';
import 'package:boorusphere/presentation/screens/post/post_toolbox.dart';
import 'package:boorusphere/presentation/screens/post/post_unknown.dart';
import 'package:boorusphere/presentation/screens/post/post_video.dart';
import 'package:boorusphere/presentation/screens/post/post_viewer_controller.dart';
import 'package:boorusphere/presentation/utils/entity/content.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:boorusphere/presentation/widgets/slidefade_visibility.dart';
import 'package:boorusphere/presentation/widgets/styled_overlay_region.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class EnhancedPostViewer extends HookConsumerWidget {
  const EnhancedPostViewer({
    super.key,
    required this.initial,
    required this.posts,
    this.swipeMode = SwipeMode.horizontal,
    this.swipeThreshold = 100.0,
    this.enableSwipeToDetails = true,
    this.enableSwipeToDismiss = true,
  });

  final int initial;
  final Iterable<Post> posts;
  final SwipeMode swipeMode;
  final double swipeThreshold;
  final bool enableSwipeToDetails;
  final bool enableSwipeToDismiss;

  static void open(
    BuildContext context, {
    required int index,
    required Iterable<Post> posts,
    SwipeMode swipeMode = SwipeMode.horizontal,
    double swipeThreshold = 100.0,
    bool enableSwipeToDetails = true,
    bool enableSwipeToDismiss = true,
  }) {
    // Capture the container before pushing the route
    final container = ProviderScope.containerOf(context);
    context.navigator.push(
      SlidePageRoute(
        opaque: false,
        type: SlidePageType.close,
        builder: (context) {
          return UncontrolledProviderScope(
            container: container,
            child: EnhancedPostViewer(
              initial: index,
              posts: posts,
              swipeMode: swipeMode,
              swipeThreshold: swipeThreshold,
              enableSwipeToDetails: enableSwipeToDetails,
              enableSwipeToDismiss: enableSwipeToDismiss,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timelineController = ref.watch(timelineControllerProvider);
    final session = ref.watch(searchSessionProvider);
    const loadMoreThreshold = 90;
    final postsList = posts.toList();

    final controller = useMemoized(
      () => PostViewerController(
        initialPage: initial,
        totalPages: postsList.length,
        swipeMode: swipeMode,
        viewMode: swipeMode == SwipeMode.vertical
            ? ViewMode.vertical
            : ViewMode.horizontal,
      ),
      [initial, postsList.length, swipeMode],
    );

    // Sheet controller for details
    final sheetController = useMemoized(DraggableScrollableController.new);
    final sheetExpanded = useState(false);

    // Post notifier for details sheet
    final currentPostNotifier = useMemoized(
      () => ValueNotifier<Post>(
          postsList.isNotEmpty ? postsList[initial] : Post.empty),
      [postsList],
    );

    useEffect(() {
      void listener() {
        final size = sheetController.size;
        sheetExpanded.value = size > 0.1;

        // Hide overlay when sheet is expanded
        if (size > 0.1) {
          controller.forceHideUI();
        } else {
          controller.restoreUI();
        }
      }

      sheetController.addListener(listener);
      return () => sheetController.removeListener(listener);
    }, [sheetController]);

    final fullscreen = ref.watch(fullscreenStateProvider);
    final showAppbar = useState(true);
    final isLoadingMore = useState(false);
    final loadMore = timelineController.onLoadMore;
    final loadOriginal =
        ref.watch(contentSettingStateProvider.select((it) => it.loadOriginal));
    final precachePosts = usePrecachePosts(ref, posts);

    final isVerticalMode = swipeMode == SwipeMode.vertical;
    final isLargeScreen = MediaQuery.of(context).size.width > 600;

    useEffect(() {
      showAppbar.value = !fullscreen;
    }, [fullscreen]);

    useEffect(() {
      controller.pageController.addListener(() {
        final page = controller.pageController.page;

        final pageNum = page?.round();
        if (pageNum != null && pageNum != controller.page) {
          controller.updateCurrentPage(pageNum);
          timelineController.scrollTo(pageNum);

          // Reset sheet when page changes
          if (sheetController.isAttached && sheetController.size > 0) {
            sheetController.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
            );
          }
        }
      });

      Future(() => timelineController.scrollTo(initial));
      WakelockPlus.enable();
      return () {
        WakelockPlus.disable();
        controller.dispose();
        currentPostNotifier.dispose();
      };
    }, []);

    void expandSheet() {
      if (sheetController.isAttached) {
        sheetController.animateTo(
          0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }

    void handlePostTap() {
      if (sheetExpanded.value) {
        sheetController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      controller.toggleOverlay();
      ref.read(fullscreenStateProvider.notifier).toggle();
    }

    VoidCallback? onSwipeUp;
    VoidCallback? onSwipeDown;
    if (!isVerticalMode) {
      if (enableSwipeToDetails) {
        onSwipeUp = expandSheet;
      }
      if (enableSwipeToDismiss) {
        onSwipeDown = () {
          Navigator.of(context).maybePop();
        };
      }
    }

    return PopScope(
      canPop: !sheetExpanded.value,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && sheetExpanded.value) {
          // Close sheet instead of popping
          await sheetController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
          return;
        }
        ref.watch(fullscreenStateProvider.notifier).reset();
        context.scaffoldMessenger.removeCurrentSnackBar();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: StyledOverlayRegion(
          nightMode: true,
          child: Stack(
            children: [
              // Main content
              Positioned.fill(
                child: PageView.builder(
                    controller: controller.pageController,
                    scrollDirection:
                        isVerticalMode ? Axis.vertical : Axis.horizontal,
                    // Custom physics consult `canSwipeListenable` on
                    // every drag attempt instead of being swapped via
                    // a parent rebuild. The previous
                    // `ListenableBuilder` approach replaced the
                    // physics object on every zoom/zoom-out, which
                    // could leave the underlying [Scrollable] in an
                    // ambiguous state if the listenable toggled
                    // mid-gesture. This way the `PageView` is built
                    // once and its drag-acceptance is reactive.
                    physics: _PageViewerScrollPhysics(
                      canSwipe: controller.canSwipeListenable,
                    ),
                    allowImplicitScrolling: true,
                    onPageChanged: (index) async {
                      // The new page starts at scale 1, so swipe should
                      // be available again. Re-enabling here covers the
                      // edge case where the previous page disabled it
                      // and was unmounted before its
                      // gestureDetailsIsChanged could fire the reset.
                      controller.enableSwipe();
                      SchedulerBinding.instance
                          .addPostFrameCallback((timeStamp) {
                        if (context.mounted) {
                          controller.updateCurrentPage(index);
                          // Update post notifier
                          if (postsList.isNotEmpty &&
                              index < postsList.length) {
                            currentPostNotifier.value = postsList[index];
                          }
                        }
                      });

                      context.scaffoldMessenger.hideCurrentSnackBar();

                      if (loadMore == null) return;

                      final offset = index + 1;
                      final threshold =
                          postsList.length / 100 * (100 - loadMoreThreshold);
                      if (offset + threshold > postsList.length - 1) {
                        isLoadingMore.value = true;
                        unawaited(loadMore());
                        await Future.delayed(const Duration(milliseconds: 300),
                            () {
                          if (context.mounted) {
                            isLoadingMore.value = false;
                          }
                        });
                      }
                    },
                    itemCount: postsList.length,
                    itemBuilder: (context, index) {
                      precachePosts(index, loadOriginal);

                      final post = postsList[index];
                      final Widget widget;

                      switch (post.content.type) {
                        case PostType.photo:
                        case PostType.gif:
                          widget = PostImage(
                            key: ValueKey('image_${post.id}_${post.serverId}'),
                            post: post,
                            onZoomChanged: (isZoomed) {
                              // Disable PageView swipe while the image
                              // is zoomed in so panning the zoomed
                              // image cannot accidentally page to the
                              // next post.
                              if (isZoomed) {
                                controller.disableSwipe();
                              } else {
                                controller.enableSwipe();
                              }
                            },
                            onTap: handlePostTap,
                            onSwipeUp: onSwipeUp,
                            onSwipeDown: onSwipeDown,
                          );
                        case PostType.video:
                          widget = PostVideo(
                            key: ValueKey('video_${post.id}_${post.serverId}'),
                            post: post,
                            onToolboxVisibilityChange: (visible) {},
                          );
                        default:
                          widget = PostUnknown(
                            key:
                                ValueKey('unknown_${post.id}_${post.serverId}'),
                            post: post,
                          );
                      }

                      return HeroMode(
                        key: ValueKey('hero_${post.id}_${post.serverId}'),
                        enabled: index == controller.page,
                        child: RepaintBoundary(
                          child: widget,
                        ),
                      );
                    }),
              ),
              // Overlay UI
              ValueListenableBuilder<int>(
                valueListenable: controller.pageListenable,
                builder: (context, currentPageIndex, child) {
                  final post = postsList.isNotEmpty
                      ? postsList[currentPageIndex]
                      : Post.empty;

                  return Stack(
                    children: [
                      // Top app bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ListenableBuilder(
                          listenable: controller.overlayShownListenable,
                          builder: (context, child) => SlideFadeVisibility(
                            direction: HidingDirection.toTop,
                            visible: controller.overlayShownListenable.value &&
                                showAppbar.value,
                            child: _PostAppBar(
                              subtitle: post.describeTags,
                              title: isLoadingMore.value
                                  ? '#${currentPageIndex + 1} of (loading...)'
                                  : '#${currentPageIndex + 1} of ${postsList.length}',
                              swipeMode: swipeMode,
                            ),
                          ),
                        ),
                      ),
                      // Bottom toolbox
                      if (!post.content.isVideo)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: ListenableBuilder(
                            listenable: controller.overlayShownListenable,
                            builder: (context, child) => SlideFadeVisibility(
                              direction: HidingDirection.toBottom,
                              visible:
                                  controller.overlayShownListenable.value &&
                                      !fullscreen,
                              child: PostToolbox(
                                key: ValueKey(
                                    'toolbox_${post.id}_${post.serverId}'),
                                post,
                              ),
                            ),
                          ),
                        ),
                      // Navigation buttons for desktop
                      if (isLargeScreen && !isVerticalMode)
                        ..._buildNavigationButtons(controller, isVerticalMode),
                    ],
                  );
                },
              ),
              // Details sheet
              PostDetailsSheet(
                postNotifier: currentPostNotifier,
                sheetController: sheetController,
                session: session,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNavigationButtons(
      PostViewerController controller, bool isVerticalMode) {
    return [
      ValueListenableBuilder<int>(
        valueListenable: controller.pageListenable,
        builder: (context, page, child) => Positioned(
          right: 16,
          top: 0,
          bottom: 0,
          child: Center(
            child: Visibility(
              visible: !controller.isLastPage,
              child: FloatingActionButton(
                mini: true,
                onPressed: () => controller.nextPage(),
                child: Icon(
                  isVerticalMode
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                ),
              ),
            ),
          ),
        ),
      ),
      ValueListenableBuilder<int>(
        valueListenable: controller.pageListenable,
        builder: (context, page, child) => Positioned(
          left: 16,
          top: 0,
          bottom: 0,
          child: Center(
            child: Visibility(
              visible: !controller.isFirstPage,
              child: FloatingActionButton(
                mini: true,
                onPressed: () => controller.previousPage(),
                child: Icon(
                  isVerticalMode
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_left,
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _PostAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _PostAppBar({
    required this.title,
    required this.subtitle,
    required this.swipeMode,
  });

  final String title;
  final String subtitle;
  final SwipeMode swipeMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomLeft,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w300),
                    ),
                  ),
                  Icon(
                    swipeMode == SwipeMode.vertical
                        ? Icons.swap_vert
                        : Icons.swap_horiz,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 64);
}

/// Page-snap scroll physics whose drag-acceptance is gated by a
/// [ValueListenable]. Built once and consulted reactively on every
/// pointer-down — the [PageView] never needs to be rebuilt to toggle
/// between "swipeable" and "locked" states.
class _PageViewerScrollPhysics extends PageScrollPhysics {
  const _PageViewerScrollPhysics({
    required this.canSwipe,
    super.parent,
  });

  final ValueListenable<bool> canSwipe;

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    return canSwipe.value && super.shouldAcceptUserOffset(position);
  }

  @override
  _PageViewerScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _PageViewerScrollPhysics(
      canSwipe: canSwipe,
      parent: buildParent(ancestor),
    );
  }
}
