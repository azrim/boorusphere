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
import 'package:flutter/gestures.dart';
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
              // Pull-to-dismiss shell wrapping PageView + overlay UI.
              // The PostDetailsSheet sits OUTSIDE the shell so it
              // doesn't translate / scale with the dismiss gesture.
              Positioned.fill(
                child: _PostViewerPullToDismissShell(
                  canPullListenable: controller.canSwipeListenable,
                  onSwipeUp: onSwipeUp,
                  onDismiss: onSwipeDown,
                  child: Stack(
                    children: [
                      // Main content
                      Positioned.fill(
                        child: ListenableBuilder(
                  listenable: controller.canSwipeListenable,
                  builder: (context, _) => PageView.builder(
                    controller: controller.pageController,
                    scrollDirection:
                        isVerticalMode ? Axis.vertical : Axis.horizontal,
                    // Swap physics objects on zoom toggle. `Scrollable`
                    // re-evaluates `physics.shouldAcceptUserOffset(position)`
                    // inside `_updatePosition()` on `didUpdateWidget`, so
                    // a fresh physics instance is what actually causes the
                    // `HorizontalDragGestureRecognizer` (or vertical, for
                    // vertical-mode) to be uninstalled while zoomed.
                    physics: controller.canSwipeListenable.value
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
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
                            // Vertical drag (swipe-up / swipe-down /
                            // pull-to-dismiss) is now owned by the
                            // route-level _PostViewerPullToDismissShell
                            // so we don't wire onSwipeUp / onSwipeDown
                            // here anymore.
                          );
                        case PostType.video:
                          widget = PostVideo(
                            key: ValueKey('video_${post.id}_${post.serverId}'),
                            post: post,
                            onToolboxVisibilityChange: (visible) {},
                            onShowDetails: expandSheet,
                            // See note above on PostImage — vertical
                            // drag is route-level now.
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
                    },
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
                                onShowDetails: expandSheet,
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
              // Details sheet (sits outside the pull-to-dismiss shell
              // so it doesn't translate / scale with the dismiss gesture)
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

/// Route-level pull-to-dismiss shell that owns ALL vertical-drag
/// gestures for the post viewer:
///
/// * **Slow drag downward** — accumulates offset and elastically
///   translates + scales the wrapped content. On release, if the
///   pulled distance exceeds [_dismissDistance] OR the release
///   velocity exceeds [_flingVelocity], [onDismiss] fires; otherwise
///   the content snaps back to origin via a brief easeOutCubic
///   animation.
/// * **Fast fling upward** — when offset is at origin and the release
///   velocity is below `-[_flingVelocity]`, [onSwipeUp] fires (used
///   for opening the details sheet).
/// * **Fast fling downward** — folds into the dismiss path above.
///
/// The shell is suspended (recognizer not mounted) while the wrapped
/// post is zoomed, so [InteractiveViewer]'s pan recognizer wins
/// uncontested. This is gated via the same [canPullListenable] used
/// by `PageView`'s scroll-physics swap.
class _PostViewerPullToDismissShell extends StatefulWidget {
  const _PostViewerPullToDismissShell({
    required this.child,
    required this.canPullListenable,
    required this.onSwipeUp,
    required this.onDismiss,
  });

  final Widget child;
  final ValueListenable<bool> canPullListenable;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onDismiss;

  @override
  State<_PostViewerPullToDismissShell> createState() =>
      _PostViewerPullToDismissShellState();
}

class _PostViewerPullToDismissShellState
    extends State<_PostViewerPullToDismissShell>
    with SingleTickerProviderStateMixin {
  /// Distance (logical px) past which a slow drag-release dismisses.
  static const double _dismissDistance = 120;

  /// Release velocity (px/s) past which a fling dismisses (downward) or
  /// opens details (upward).
  static const double _flingVelocity = 500;

  /// Distance over which the elastic transform fades the background to
  /// 40 % opacity and shrinks the content to 85 %.
  static const double _maxFadeDistance = 360;

  final ValueNotifier<double> _offset = ValueNotifier(0);
  late final AnimationController _resetCtrl;
  Animation<double>? _resetAnim;
  void Function()? _resetTickListener;

  @override
  void initState() {
    super.initState();
    _resetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _stopResetAnim();
    _resetCtrl.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _stopResetAnim() {
    if (_resetTickListener != null && _resetAnim != null) {
      _resetAnim!.removeListener(_resetTickListener!);
    }
    _resetTickListener = null;
    _resetAnim = null;
    if (_resetCtrl.isAnimating) _resetCtrl.stop();
  }

  void _onUpdate(DragUpdateDetails d) {
    _stopResetAnim();
    final next = _offset.value + d.delta.dy;
    // Don't translate upward from origin — the content has nowhere to
    // go up. Upward swipe-up is detected by velocity on release.
    _offset.value = next < 0 ? 0 : next;
  }

  void _onEnd(DragEndDetails d) {
    final velocity = d.velocity.pixelsPerSecond.dy;
    final offset = _offset.value;

    // Dismiss path — pulled past threshold or fast fling down.
    if (widget.onDismiss != null &&
        (offset > _dismissDistance || velocity > _flingVelocity)) {
      widget.onDismiss!.call();
      return;
    }

    // Swipe-up path — at origin with a fast fling up.
    if (widget.onSwipeUp != null &&
        offset == 0 &&
        velocity < -_flingVelocity) {
      widget.onSwipeUp!.call();
      return;
    }

    // Snap back to origin.
    _animateReset();
  }

  void _animateReset() {
    if (_offset.value == 0) return;
    final start = _offset.value;
    _resetAnim = Tween<double>(begin: start, end: 0)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_resetCtrl);
    void tick() => _offset.value = _resetAnim!.value;
    _resetTickListener = tick;
    _resetAnim!.addListener(tick);
    _resetCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.canPullListenable,
      builder: (context, _) {
        final canPull = widget.canPullListenable.value;
        final body = ValueListenableBuilder<double>(
          valueListenable: _offset,
          builder: (_, dy, child) {
            final t = (dy / _maxFadeDistance).clamp(0.0, 1.0);
            return ColoredBox(
              color: Color.fromRGBO(0, 0, 0, 1.0 - t * 0.6),
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Transform.scale(
                  scale: 1.0 - t * 0.15,
                  child: child,
                ),
              ),
            );
          },
          child: widget.child,
        );

        // No vertical drag gating while zoomed — InteractiveViewer's
        // pan owns vertical motion in that mode.
        if (!canPull) return body;

        return RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: <Type, GestureRecognizerFactory>{
            _PullToDismissDragRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    _PullToDismissDragRecognizer>(
              _PullToDismissDragRecognizer.new,
              (instance) {
                instance.onUpdate = _onUpdate;
                instance.onEnd = _onEnd;
              },
            ),
          },
          child: body,
        );
      },
    );
  }
}

/// Vertical-drag recognizer for the route-level pull-to-dismiss shell.
/// Rejects itself the moment a 2nd pointer arrives so that
/// [InteractiveViewer]'s scale recognizer wins multi-touch uncontested
/// (matches the shape of the recognizer in [PostImage]).
class _PullToDismissDragRecognizer extends VerticalDragGestureRecognizer {
  _PullToDismissDragRecognizer({super.debugOwner});

  int _activePointers = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers > 1) {
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
      _activePointers--;
      return;
    }
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _activePointers = (_activePointers - 1).clamp(0, 10);
    }
    super.handleEvent(event);
  }
}
