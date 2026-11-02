import 'dart:async';
import 'dart:math';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/routes/route_visibility.dart';
import 'package:boorusphere/presentation/routes/slide_page_route.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/screens/post/hooks/precache_posts.dart';
import 'package:boorusphere/presentation/screens/post/post_details_sheet.dart';
import 'package:boorusphere/presentation/screens/post/post_media.dart';
import 'package:boorusphere/presentation/screens/post/post_toolbox.dart';
import 'package:boorusphere/presentation/screens/post/post_viewer_controller.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:boorusphere/presentation/utils/slideshow.dart';
import 'package:boorusphere/presentation/widgets/slidefade_visibility.dart';
import 'package:boorusphere/presentation/widgets/styled_overlay_region.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:boorusphere/utils/volume_keys.dart';
import 'package:boorusphere/utils/wakelock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    // Keep the list identity stable across rebuilds: the slideshow and the
    // page listener compare posts by index, and re-copying the iterable on
    // every provider tick would also re-register their status listeners.
    final postsList = useMemoized(posts.toList, [posts]);

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

    // Whether this viewer is the route on screen. Another timeline can be
    // pushed above it (related posts, tag search) while it stays mounted, so
    // the process-wide hooks below have to know when to let go.
    final routeVisible = useRouteVisible(
      ModalRoute.of(context),
      appRouteObserver,
    );

    final slideshowInterval = ref.watch(
      contentSettingStateProvider.select((it) => it.slideshowInterval),
    );
    final slideshowDirection = ref.watch(
      contentSettingStateProvider.select((it) => it.slideshowDirection),
    );
    final volumeKeyNavigation = ref.watch(
      contentSettingStateProvider.select((it) => it.volumeKeyNavigation),
    );

    final slideshowPlaying = useState(false);
    final slideshowAdvanceInFlight = useRef(false);
    final slideshowTarget = useRef<int?>(null);
    final random = useMemoized(Random.new);
    final slideshowAnimator = useAnimationController(
      duration: Duration(seconds: slideshowInterval),
    );

    bool isVideoPage(int index) =>
        index >= 0 &&
        index < postsList.length &&
        postsList[index].content.isVideo;

    void stopSlideshow() {
      slideshowTarget.value = null;
      if (!slideshowPlaying.value) return;
      slideshowAnimator.stop();
      slideshowPlaying.value = false;
    }

    void startSlideshow() {
      if (postsList.isEmpty || isVideoPage(controller.page)) return;
      slideshowPlaying.value = true;
      slideshowAnimator.forward(from: 0);
    }

    void toggleSlideshow() {
      if (slideshowPlaying.value) {
        stopSlideshow();
      } else {
        startSlideshow();
      }
    }

    Future<void> advanceSlideshow() async {
      if (!slideshowPlaying.value) return;

      final next = nextSlideshowPage(
        current: controller.page,
        total: postsList.length,
        direction: slideshowDirection,
        random: random,
      );
      if (next == null) {
        stopSlideshow();
        return;
      }

      slideshowTarget.value = next;
      slideshowAdvanceInFlight.value = true;
      try {
        await controller.animateToPage(next);
      } finally {
        slideshowAdvanceInFlight.value = false;
      }

      if (!slideshowPlaying.value) return;
      if (isVideoPage(next)) {
        slideshowTarget.value = null;
        stopSlideshow();
        return;
      }
      slideshowAnimator.forward(from: 0);
    }

    // Sheet controller for details
    final sheetController = useMemoized(DraggableScrollableController.new);
    final sheetExpanded = useState(false);
    // Whether the visible image is zoomed in. Back has to undo that before
    // it leaves the viewer, so the state lives here as well as in PostMedia.
    final zoomed = useState(false);
    final zoomResetTick = useMemoized(() => ValueNotifier<int>(0));

    // Post notifier for details sheet. Empty deps because the notifier
    // must survive parent rebuilds; `onPageChanged` updates its .value
    // directly. [postsList] was a wrong dep: posts.toList() creates a
    // new List each build, causing useMemoized to recreate the notifier
    // (resetting to the initial post) whenever a watched provider fires.
    final currentPostNotifier = useMemoized(
      () => ValueNotifier<Post>(
        postsList.isNotEmpty ? postsList[initial] : Post.empty,
      ),
    );

    useEffect(() {
      void listener() {
        final size = sheetController.size;
        sheetExpanded.value = size > 0.1;

        // Hide overlay when sheet is expanded
        if (size > 0.1) {
          controller.forceHideUI();
          // Reading the post details is a deliberate stop, not a pause the
          // slideshow should resume from on its own once the sheet closes.
          stopSlideshow();
        } else {
          controller.restoreUI();
        }
      }

      sheetController.addListener(listener);
      return () => sheetController.removeListener(listener);
    }, [sheetController, slideshowAnimator]);

    final fullscreen = ref.watch(fullscreenStateProvider);
    final showAppbar = useState(true);
    final loadOriginal = ref.watch(
      contentSettingStateProvider.select((it) => it.loadOriginal),
    );
    final precachePosts = usePrecachePosts(ref, posts);

    final isVerticalMode = swipeMode == SwipeMode.vertical;
    final isLargeScreen = MediaQuery.sizeOf(context).width > 600;

    useEffect(() => zoomResetTick.dispose, [zoomResetTick]);

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
              duration: DesignTokens.durationFast,
              curve: Curves.easeOutCubic,
            );
          }
        }
      });

      Future(() => timelineController.scrollTo(initial));
      return () {
        controller.dispose();
        currentPostNotifier.dispose();
      };
    }, []);

    useEffect(() {
      void onStatus(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          unawaited(advanceSlideshow());
        }
      }

      slideshowAnimator.addStatusListener(onStatus);
      return () => slideshowAnimator.removeStatusListener(onStatus);
    }, [slideshowAnimator, postsList, slideshowDirection]);

    // A new interval takes effect from the current post instead of waiting for
    // the old, possibly minutes-long, cycle to finish.
    useEffect(() {
      slideshowAnimator.duration = Duration(seconds: slideshowInterval);
      if (slideshowPlaying.value) {
        slideshowAnimator.forward(from: 0);
      }
      return null;
    }, [slideshowInterval]);

    final volumeKeysActive =
        volumeKeyNavigation && !sheetExpanded.value && routeVisible;
    // Capture follows the viewer, not the process. A covered page must not
    // keep answering: a related post can push a timeline above it, where the
    // buttons belong to media volume again. Stacked viewers hand the keys back
    // to the one underneath when they close, which a plain enable/disable
    // switch would lose. The handler reads the sheet and zoom state when a
    // press arrives, so it always reflects what is on screen then.
    useEffect(() {
      if (!volumeKeysActive) {
        unawaited(VolumeKeys.release(controller));
        return null;
      }

      unawaited(
        VolumeKeys.acquire(controller, (direction) {
          // A zoomed image owns the volume keys' neighbour gestures; stepping
          // the page while the user is panning would lose their place.
          if (sheetExpanded.value || zoomed.value) return;
          if (direction == VolumeKeyDirection.up) {
            unawaited(controller.nextPage());
          } else {
            unawaited(controller.previousPage());
          }
        }),
      );
      return null;
    }, [volumeKeysActive, controller]);
    useEffect(() {
      return () => unawaited(VolumeKeys.release(controller));
    }, [controller]);

    // The screen-on request belongs to the visible viewer as well: a covered
    // page must not keep the display awake above it, and a stacked viewer must
    // not turn the request off for this one when it closes. The manager counts
    // holders, so the covered page letting go first cannot cancel the viewer
    // that was just pushed on top.
    useEffect(() {
      if (routeVisible) {
        wakelockManager.acquire(controller);
      } else {
        wakelockManager.release(controller);
      }
      return null;
    }, [routeVisible, controller]);
    useEffect(() {
      return () => wakelockManager.release(controller);
    }, [controller]);

    // Immersive mode belongs to the screen this viewer owns. Covering it with
    // a related timeline used to keep the system bars hidden on that page, and
    // a viewer pushed from it opened already fullscreen because the flag
    // outlives the viewer that set it. Let go as soon as this route is no
    // longer on top; entering fullscreen again is a deliberate action.
    useEffect(() {
      if (!routeVisible) {
        ref.read(fullscreenStateProvider.notifier).reset();
      }
      return null;
    }, [routeVisible]);

    void expandSheet() {
      if (sheetController.isAttached) {
        sheetController.animateTo(
          PostDetailsSheet.openSize,
          duration: DesignTokens.durationNormal,
          curve: Curves.easeOutCubic,
        );
      }
    }

    void handlePostTap() {
      if (sheetExpanded.value) {
        sheetController.animateTo(
          0,
          duration: DesignTokens.durationFast,
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
      // Back closes the sheet, then resets a zoom, then leaves the viewer.
      canPop: !sheetExpanded.value && !zoomed.value,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          ref.read(fullscreenStateProvider.notifier).reset();
          context.scaffoldMessenger.removeCurrentSnackBar();
          return;
        }

        if (sheetExpanded.value) {
          // Close sheet instead of popping
          await sheetController.animateTo(
            0,
            duration: DesignTokens.durationFast,
            curve: Curves.easeOutCubic,
          );
          return;
        }

        zoomResetTick.value++;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: StyledOverlayRegion(
          nightMode: true,
          child: Stack(
            children: [
              // PageView + overlay UI. Pull-to-dismiss was tried at the
              // route level in 2.0.5 but its recognizer turned out to
              // be unable to consistently win the gesture arena over
              // [InteractiveViewer]'s built-in scale recognizer at
              // scale = 1, so vertical swipes were silently swallowed.
              // 2.0.12 reverts to the proven per-surface gesture
              // wiring used in v2.0.4: vertical drag is owned by
              // [PostMedia]'s image and video surfaces, both of which
              // self-reject on multi-touch so pinch-to-zoom is
              // uncontested.
              Positioned.fill(
                child: Stack(
                  children: [
                    // Main content
                    Positioned.fill(
                      child: ListenableBuilder(
                        listenable: controller.canSwipeListenable,
                        builder: (context, _) => PageView.builder(
                          controller: controller.pageController,
                          scrollDirection: isVerticalMode
                              ? Axis.vertical
                              : Axis.horizontal,
                          // Swap physics objects on zoom toggle. `Scrollable`
                          // re-evaluates `physics.shouldAcceptUserOffset(position)`
                          // inside `_updatePosition()` on `didUpdateWidget`, so
                          // a fresh physics instance is what actually causes the
                          // `HorizontalDragGestureRecognizer` (or vertical, for
                          // vertical-mode) to be uninstalled while zoomed.
                          physics: controller.canSwipeListenable.value
                              ? const _GentlePageScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          allowImplicitScrolling: true,
                          onPageChanged: (index) {
                            // The new page starts at scale 1, so swipe should
                            // be available again. Re-enabling here covers the
                            // edge case where the previous page disabled it
                            // and was unmounted before its
                            // gestureDetailsIsChanged could fire the reset.
                            controller.enableSwipe();

                            // The zoom belonged to the page the viewer just
                            // left. Keeping the claim would make Back check a
                            // scale that is no longer on screen, so a viewer
                            // that was zoomed and then paged (nav buttons on a
                            // large screen) could not be closed by Back at all.
                            // The tick folds the old page back to fit as well,
                            // so its retained transform cannot disagree with
                            // the cleared claim when it is paged back into view.
                            zoomed.value = false;
                            zoomResetTick.value++;

                            // A page the slideshow did not ask for is a manual
                            // step (swipe, volume key, nav button): the user
                            // has taken over, so stop instead of fighting them.
                            if (slideshowPlaying.value) {
                              if (!slideshowAdvanceInFlight.value) {
                                if (slideshowTarget.value == index) {
                                  slideshowTarget.value = null;
                                  if (isVideoPage(index)) stopSlideshow();
                                } else {
                                  slideshowTarget.value = null;
                                  stopSlideshow();
                                }
                              }
                            }

                            SchedulerBinding.instance.addPostFrameCallback((
                              timeStamp,
                            ) {
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
                          },
                          itemCount: postsList.length,
                          itemBuilder: (context, index) {
                            precachePosts(index, loadOriginal);

                            final post = postsList[index];
                            final widget = PostMedia(
                              key: ValueKey(
                                'media_${post.id}_${post.serverId}',
                              ),
                              post: post,
                              isRouteVisible: routeVisible,
                              zoomResetSignal: zoomResetTick,
                              onZoomChanged: (isZoomed) {
                                zoomed.value = isZoomed;
                                // Disable PageView swipe while the image
                                // is zoomed in so panning the zoomed
                                // image cannot accidentally page to the
                                // next post. Same listenable is also
                                // consulted by the route-level pull-to-
                                // dismiss shell to suspend its vertical
                                // drag recognizer while zoomed.
                                if (isZoomed) {
                                  controller.disableSwipe();
                                } else {
                                  controller.enableSwipe();
                                }
                              },
                              onTap: handlePostTap,
                              onShowDetails: expandSheet,
                              onSwipeUp: onSwipeUp,
                              onSwipeDown: onSwipeDown,
                            );

                            return HeroMode(
                              key: ValueKey('hero_${post.id}_${post.serverId}'),
                              enabled: index == controller.page,
                              child: RepaintBoundary(child: widget),
                            );
                          },
                        ),
                      ),
                    ),
                    // Slideshow progress. Kept outside the overlay stack so
                    // it stays visible while the chrome is hidden; the play
                    // button in the app bar carries the accessible state.
                    if (slideshowPlaying.value)
                      Positioned(
                        top: MediaQuery.paddingOf(context).top,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: AnimatedBuilder(
                              animation: slideshowAnimator,
                              builder: (context, _) => LinearProgressIndicator(
                                value: slideshowAnimator.value,
                                minHeight: 2,
                                backgroundColor: Colors.white24,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
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
                                builder: (context, child) =>
                                    SlideFadeVisibility(
                                      direction: HidingDirection.toTop,
                                      visible:
                                          controller
                                              .overlayShownListenable
                                              .value &&
                                          showAppbar.value,
                                      child: _PostAppBar(
                                        subtitle: post.describeTags,
                                        title: context.t.postCounter(
                                          index: currentPageIndex + 1,
                                          total: postsList.length,
                                        ),
                                        swipeMode: swipeMode,
                                        slideshowPlaying:
                                            slideshowPlaying.value,
                                        onToggleSlideshow: post.content.isVideo
                                            ? null
                                            : toggleSlideshow,
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
                                  builder: (context, child) =>
                                      SlideFadeVisibility(
                                        direction: HidingDirection.toBottom,
                                        visible:
                                            controller
                                                .overlayShownListenable
                                                .value &&
                                            !fullscreen,
                                        child: PostToolbox(
                                          key: ValueKey(
                                            'toolbox_${post.id}_${post.serverId}',
                                          ),
                                          post,
                                          onShowDetails: expandSheet,
                                          session: post.serverId,
                                        ),
                                      ),
                                ),
                              ),
                            // Navigation buttons for desktop
                            if (isLargeScreen && !isVerticalMode)
                              ..._buildNavigationButtons(
                                controller,
                                isVerticalMode,
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Details sheet sits at top level so any future overlay
              // additions don't affect its draggable behavior.
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
    PostViewerController controller,
    bool isVerticalMode,
  ) {
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
              child: IconButton.filledTonal(
                tooltip: context.t.pagination.next,
                iconSize: 28,
                onPressed: () => controller.nextPage(),
                icon: Icon(
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
              child: IconButton.filledTonal(
                tooltip: context.t.pagination.previous,
                iconSize: 28,
                onPressed: () => controller.previousPage(),
                icon: Icon(
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

class _PostAppBar extends StatelessWidget {
  const _PostAppBar({
    required this.title,
    required this.subtitle,
    required this.swipeMode,
    required this.slideshowPlaying,
    this.onToggleSlideshow,
  });

  final String title;
  final String subtitle;
  final SwipeMode swipeMode;
  final bool slideshowPlaying;

  /// Null on video posts: the slideshow pauses there rather than advancing
  /// in the middle of playback.
  final VoidCallback? onToggleSlideshow;

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
        // The title carries two lines, so the toolbar grows with the system
        // font scale instead of clipping them at the default height.
        toolbarHeight: MediaQuery.textScalerOf(context).scale(kToolbarHeight),
        actions: [
          if (onToggleSlideshow != null)
            IconButton(
              tooltip: slideshowPlaying
                  ? context.t.viewer.stopSlideshow
                  : context.t.viewer.startSlideshow,
              onPressed: onToggleSlideshow,
              icon: Icon(
                slideshowPlaying
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
              ),
            ),
        ],
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PageView physics that requires a more deliberate gesture before
/// committing a page change, mitigating the user complaint that the
/// default `PageScrollPhysics` page-flips on the slightest soft swipe
/// while browsing posts.
///
/// Two thresholds, both higher than the framework default:
///
/// * **Distance**: a slow drag-release commits to the next page only
///   when the user has crossed [_commitThreshold] (60 %) of the page
///   width. Default `PageScrollPhysics` uses `roundToDouble()` which
///   commits at 50 %.
/// * **Velocity**: a fling commits regardless of distance only when
///   the release velocity exceeds [_flingVelocity] (400 px/s). Default
///   `Tolerance.velocity` is roughly 20–50 px/s, so even a barely
///   perceptible flick used to commit a page change.
class _GentlePageScrollPhysics extends PageScrollPhysics {
  const _GentlePageScrollPhysics({super.parent});

  /// Fraction of the page width past which a low-velocity drag commits
  /// to the adjacent page. Below this fraction, the drag snaps back to
  /// the page the user came from.
  static const double _commitThreshold = 0.6;

  /// Release velocity (px/s) past which a fling commits to the next
  /// page regardless of drag distance.
  static const double _flingVelocity = 400;

  /// Stiff, slightly under-damped spring used for the page-snap
  /// animation. Tuned so the simulation settles in roughly 80 ms instead
  /// of the framework default (~280 ms).
  ///
  /// User report (2.0.14): "the swipe gesture is done, I swipe and
  /// release my finger. but the animation isn't done immediately. the
  /// content is like almost 90 % loaded but animation still not done.
  /// but user will be doing another gesture like swipe up, because in
  /// their eyes it's already done. ... that make any gesture is
  /// considered as swipe left or right gesture."
  ///
  /// Diagnosis: while the snap is animating, [Scrollable] is in a
  /// [BallisticScrollActivity]. As soon as the user touches down (even
  /// before they move) the drag recognizer's `_handleDragDown` fires,
  /// holds the ballistic, and the [HorizontalDragGestureRecognizer] is
  /// immediately a contender for the next motion. Any horizontal jitter
  /// at the start of the follow-up gesture wins the arena and the page
  /// continues animating from the frozen position. Shortening the snap
  /// to ~80 ms (essentially imperceptible) collapses the window for
  /// follow-up gesture confusion.
  ///
  /// `mass = 0.3, stiffness = 800` → ω = √(k/m) ≈ 51.6 rad/s; with
  /// damping ratio 0.95 the simulation reaches the tolerance band in
  /// roughly 4/ω ≈ 80 ms.
  static final SpringDescription _snapSpring =
      SpringDescription.withDampingRatio(
        mass: 0.3,
        stiffness: 800,
        ratio: 0.95,
      );

  /// Permissive tolerance so the spring simulation declares "done" once
  /// it is within ~3 px / 5 px·s of the target, far sooner than the
  /// framework default (~0.4 px / ~20 px·s) which keeps the simulation
  /// alive past the point any human could perceive motion. Combined
  /// with [_snapSpring], the simulation effectively terminates within
  /// 60–80 ms of release.
  static const Tolerance _snapTolerance = Tolerance(
    distance: 3.0,
    velocity: 5.0,
  );

  @override
  SpringDescription get spring => _snapSpring;

  @override
  _GentlePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _GentlePageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Defer to the parent at the scroll-extent edges (overscroll glow,
    // bounce-back, etc.), we only want to override the page-snap
    // decision in the middle of the scrollable.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final pageWidth = position.viewportDimension;
    final currentPagePosition = position.pixels / pageWidth;
    final currentFloor = currentPagePosition.floorToDouble();
    final fractionPastFloor = currentPagePosition - currentFloor;

    final double targetPage;
    if (velocity > _flingVelocity) {
      // Deliberate fling forward.
      targetPage = currentFloor + 1;
    } else if (velocity < -_flingVelocity) {
      // Deliberate fling backward.
      targetPage = currentFloor;
    } else if (fractionPastFloor >= _commitThreshold) {
      // Slow drag past the commit threshold: commit forward.
      targetPage = currentFloor + 1;
    } else {
      // Slow drag short of the commit threshold: snap back.
      targetPage = currentFloor;
    }

    final targetPixels = targetPage * pageWidth;
    if (targetPixels == position.pixels) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      targetPixels,
      velocity,
      tolerance: _snapTolerance,
    );
  }
}
