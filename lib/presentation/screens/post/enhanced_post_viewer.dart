import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/routes/slide_page_route.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/screens/post/hooks/precache_posts.dart';
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
    context.navigator.push(
      SlidePageRoute(
        opaque: false,
        type: SlidePageType.close,
        builder: (context) {
          return UncontrolledProviderScope(
            container: ProviderScope.containerOf(context),
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

    final fullscreen = ref.watch(fullscreenStateProvider);
    final showAppbar = useState(true);
    final isLoadingMore = useState(false);
    final loadMore = timelineController.onLoadMore;
    final loadOriginal =
        ref.watch(contentSettingStateProvider.select((it) => it.loadOriginal));
    final precachePosts = usePrecachePosts(ref, posts);

    // Gesture state
    final pointerCount = useState(0);
    final interacting = useState(false);
    final dragStartOffset = useState(Offset.zero);
    final dragOffset = useState(Offset.zero);

    final isVerticalMode = swipeMode == SwipeMode.vertical;
    final isLargeScreen = MediaQuery.of(context).size.width > 600;

    useEffect(() {
      showAppbar.value = !fullscreen;
    }, [fullscreen]);

    useEffect(() {
      controller.pageController.addListener(() {
        final page = controller.pageController.page;
        controller.updatePrecisePage(page);

        final pageNum = page?.round();
        if (pageNum != null && pageNum != controller.page) {
          controller.updateCurrentPage(pageNum);
          timelineController.scrollTo(pageNum);
        }
      });

      Future(() => timelineController.scrollTo(initial));
      WakelockPlus.enable();
      return () {
        WakelockPlus.disable();
        controller.dispose();
      };
    }, []);

    void openPostDetails(Post post) {
      const session = SearchSession();
      context.router.push(PostDetailsRoute(post: post, session: session));
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        ref.watch(fullscreenStateProvider.notifier).reset();
        context.scaffoldMessenger.removeCurrentSnackBar();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: StyledOverlayRegion(
          nightMode: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: controller.swipeEnabled,
                        builder: (context, swipeEnabled, child) =>
                            ValueListenableBuilder(
                          valueListenable: controller.animating,
                          builder: (context, animating, child) {
                            final canSwipe = swipeEnabled &&
                                !animating &&
                                !interacting.value;

                            return GestureDetector(
                              onTap: controller.toggleOverlay,
                              onVerticalDragStart: !isVerticalMode
                                  ? (details) {
                                      dragStartOffset.value =
                                          details.globalPosition;
                                      dragOffset.value = Offset.zero;
                                    }
                                  : null,
                              onVerticalDragUpdate: !isVerticalMode
                                  ? (details) {
                                      final delta = details.globalPosition.dy -
                                          dragStartOffset.value.dy;
                                      dragOffset.value = Offset(0, delta);
                                    }
                                  : null,
                              onVerticalDragEnd: !isVerticalMode
                                  ? (details) {
                                      final dy = dragOffset.value.dy;
                                      final velocity =
                                          details.velocity.pixelsPerSecond.dy;

                                      // Swipe up - open details (negative dy or negative velocity)
                                      if (enableSwipeToDetails &&
                                          (dy < -swipeThreshold ||
                                              velocity < -500)) {
                                        final currentPost =
                                            postsList[controller.page];
                                        dragOffset.value = Offset.zero;
                                        openPostDetails(currentPost);
                                        return;
                                      }
                                      // Swipe down - dismiss (positive dy or positive velocity)
                                      else if (enableSwipeToDismiss &&
                                          (dy > swipeThreshold ||
                                              velocity > 500)) {
                                        Navigator.of(context).maybePop();
                                        return;
                                      }

                                      // Reset
                                      dragOffset.value = Offset.zero;
                                    }
                                  : null,
                              child: ValueListenableBuilder<Offset>(
                                valueListenable: dragOffset,
                                builder: (context, offset, child) {
                                  return Transform.translate(
                                    offset: offset,
                                    child: child,
                                  );
                                },
                                child: PageView.builder(
                                  controller: controller.pageController,
                                  scrollDirection: isVerticalMode
                                      ? Axis.vertical
                                      : Axis.horizontal,
                                  physics: canSwipe
                                      ? const PageScrollPhysics()
                                      : const NeverScrollableScrollPhysics(),
                                  onPageChanged: (index) async {
                                    SchedulerBinding.instance
                                        .addPostFrameCallback((timeStamp) {
                                      if (context.mounted) {
                                        controller.updateCurrentPage(index);
                                      }
                                    });

                                    context.scaffoldMessenger
                                        .hideCurrentSnackBar();

                                    if (loadMore == null) return;

                                    final offset = index + 1;
                                    final threshold = postsList.length /
                                        100 *
                                        (100 - loadMoreThreshold);
                                    if (offset + threshold >
                                        postsList.length - 1) {
                                      isLoadingMore.value = true;
                                      await loadMore();
                                      await Future.delayed(
                                          const Duration(milliseconds: 300),
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
                                        widget = PostImage(post: post);
                                        break;
                                      case PostType.video:
                                        widget = PostVideo(
                                          post: post,
                                          onToolboxVisibilityChange: (visible) {
                                            // Handle video-specific UI changes
                                          },
                                        );
                                        break;
                                      default:
                                        widget = PostUnknown(post: post);
                                        break;
                                    }

                                    return HeroMode(
                                      enabled: index == controller.page,
                                      child: ClipRect(
                                        child: _PointerCountDetector(
                                          onCountChanged: (count) {
                                            pointerCount.value = count;
                                            interacting.value = count > 1;
                                          },
                                          child: widget,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Overlay UI
              ValueListenableBuilder(
                valueListenable: controller.currentPage,
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
                        child: ValueListenableBuilder(
                          valueListenable: controller.overlayVisible,
                          builder: (context, overlayVisible, child) =>
                              ValueListenableBuilder(
                            valueListenable: controller.forceHideOverlay,
                            builder: (context, forceHide, child) =>
                                SlideFadeVisibility(
                              direction: HidingDirection.toTop,
                              visible: overlayVisible &&
                                  !forceHide &&
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
                      ),
                      // Bottom toolbox
                      if (!post.content.isVideo)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: ValueListenableBuilder(
                            valueListenable: controller.overlayVisible,
                            builder: (context, overlayVisible, child) =>
                                ValueListenableBuilder(
                              valueListenable: controller.forceHideOverlay,
                              builder: (context, forceHide, child) =>
                                  SlideFadeVisibility(
                                direction: HidingDirection.toBottom,
                                visible:
                                    overlayVisible && !forceHide && !fullscreen,
                                child: PostToolbox(post),
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
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNavigationButtons(
      PostViewerController controller, bool isVerticalMode) {
    return [
      // Next button
      ValueListenableBuilder(
        valueListenable: controller.currentPage,
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
      // Previous button
      ValueListenableBuilder(
        valueListenable: controller.currentPage,
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
                  // Swipe mode indicator
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

class _PointerCountDetector extends StatefulWidget {
  const _PointerCountDetector({
    required this.child,
    required this.onCountChanged,
  });

  final Widget child;
  final ValueChanged<int> onCountChanged;

  @override
  State<_PointerCountDetector> createState() => _PointerCountDetectorState();
}

class _PointerCountDetectorState extends State<_PointerCountDetector> {
  int _pointerCount = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _pointerCount++;
        widget.onCountChanged(_pointerCount);
      },
      onPointerUp: (event) {
        _pointerCount--;
        widget.onCountChanged(_pointerCount);
      },
      onPointerCancel: (event) {
        _pointerCount--;
        widget.onCountChanged(_pointerCount);
      },
      child: widget.child,
    );
  }
}
