import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/screens/post/hooks/video_post.dart';
import 'package:boorusphere/presentation/screens/post/post_placeholder_image.dart';
import 'package:boorusphere/presentation/screens/post/post_toolbox.dart';
import 'package:boorusphere/presentation/screens/post/quickbar.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/entity/content.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/utils/gestures/single_pointer_vertical_drag_recognizer.dart';
import 'package:boorusphere/presentation/utils/hooks/markmayneedrebuild.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/url_validator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Dispatches a [Post] to the widget that renders its media kind.
///
/// This is the single seam the post viewer talks to: it owns the
/// `PostType` dispatch and forwards the union of gesture callbacks the
/// viewer cares about. The concrete renderers ([_PostImage], [_PostVideo],
/// [_PostUnknown]) are private to this library so the kind-specific
/// details stay encapsulated behind the seam.
class PostMedia extends StatelessWidget {
  const PostMedia({
    super.key,
    required this.post,
    this.onZoomChanged,
    this.onTap,
    this.onShowDetails,
    this.onSwipeUp,
    this.onSwipeDown,
    this.zoomResetSignal,
  });

  final Post post;

  /// Called whenever the rendered image transitions between resting (scale
  /// == 1) and zoomed-in (scale > 1) states. Used by the post viewer to
  /// disable page-swipe gestures while a zoom is active so panning a
  /// zoomed image does not accidentally swipe to the next post. Ignored by
  /// non-image kinds.
  final ValueChanged<bool>? onZoomChanged;

  /// Fired on a single-finger tap while the image is at rest (scale == 1).
  /// The post viewer uses this to toggle the in-app overlay (appbar /
  /// toolbox) and the system UI (status bar) together.
  final VoidCallback? onTap;

  /// Wired by the post viewer to expand the details sheet. Used by the
  /// video toolbox details button.
  final VoidCallback? onShowDetails;

  /// Single-finger swipe-up (fast fling) handler. The post viewer wires
  /// this to expand the details sheet.
  final VoidCallback? onSwipeUp;

  /// Single-finger swipe-down (fast fling) handler. The post viewer wires
  /// this to dismiss the route.
  final VoidCallback? onSwipeDown;

  /// Fires when the viewer wants the image back at fit-to-screen, e.g. when
  /// Back is pressed while zoomed. Ignored by non-image kinds.
  final Listenable? zoomResetSignal;

  @override
  Widget build(BuildContext context) {
    return switch (post.content.type) {
      PostType.photo || PostType.gif => _PostImage(
        post: post,
        onZoomChanged: onZoomChanged,
        onTap: onTap,
        onSwipeUp: onSwipeUp,
        onSwipeDown: onSwipeDown,
        zoomResetSignal: zoomResetSignal,
      ),
      PostType.video => _PostVideo(
        post: post,
        onShowDetails: onShowDetails,
        onSwipeUp: onSwipeUp,
        onSwipeDown: onSwipeDown,
      ),
      _ => _PostUnknown(post: post),
    };
  }
}

/// Hoisted out of `build` so we don't allocate one [ImageFilter] per
/// repaint while the user is zooming or scrolling.
final ImageFilter _kExplicitBlur = ImageFilter.blur(
  sigmaX: 5,
  sigmaY: 5,
  tileMode: TileMode.decal,
);

class _PostImage extends HookConsumerWidget {
  const _PostImage({
    required this.post,
    this.onZoomChanged,
    this.onTap,
    this.onSwipeUp,
    this.onSwipeDown,
    this.zoomResetSignal,
  });

  final Post post;

  /// Called whenever the rendered image transitions between resting (scale
  /// == 1) and zoomed-in (scale > 1) states. Used by the post viewer to
  /// disable page-swipe gestures while a zoom is active so panning a
  /// zoomed image does not accidentally swipe to the next post.
  final void Function(bool isZoomed)? onZoomChanged;

  /// Fired on a single-finger tap while the image is at rest (scale == 1).
  /// The post viewer uses this to toggle the in-app overlay (appbar /
  /// toolbox) and the system UI (status bar) together. If null, falls back
  /// to toggling [fullscreenStateProvider] only.
  final VoidCallback? onTap;

  /// Fired when the user single-finger swipes up while the image is at
  /// rest (scale == 1). The post viewer uses this to expand the details
  /// sheet.
  final VoidCallback? onSwipeUp;

  /// Fired when the user single-finger swipes down while the image is at
  /// rest (scale == 1). The post viewer uses this to dismiss the route.
  final VoidCallback? onSwipeDown;

  /// Animates the image back to fit-to-screen when the viewer asks for it.
  final Listenable? zoomResetSignal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentSetting = ref.watch(contentSettingStateProvider);
    final shouldBlurExplicit =
        contentSetting.blurExplicit && !contentSetting.blurTimelineOnly;
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final isBlur = useState(post.rating.isExplicit && shouldBlurExplicit);
    final transformController = useTransformationController();
    final zoomAnimator = useAnimationController(
      duration: context.motionDuration(const Duration(milliseconds: 150)),
    );
    final wasZoomed = useRef(false);
    // Zoom is a threshold, not a continuous value. The transform controller
    // notifies on every frame of a pinch or pan, while the gesture surface only
    // changes when the image crosses in or out of a zoom.
    final zoomedNotifier = useMemoized(() => ValueNotifier<bool>(false));
    final activePointers = useRef(0);
    final tapPosition = useRef(Offset.zero);
    final retryNonce = useState(0);
    final createdAt = useState(DateTime.now().millisecondsSinceEpoch);
    final loadState = useState<_PostImageLoadState>(
      const _PostImageLoadState.loading(null),
    );

    final deviceRatio = MediaQuery.sizeOf(context).aspectRatio;
    final imageRatio = post.aspectRatio;
    final scaleRatio = deviceRatio < imageRatio
        ? imageRatio / deviceRatio
        : deviceRatio / imageRatio;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final screenSize = MediaQuery.sizeOf(context);
    final cacheWidth = (screenSize.width * pixelRatio).round();
    final cacheHeight = (screenSize.height * pixelRatio).round();

    useEffect(() {
      void onTransformChange() {
        final scale = transformController.value.getMaxScaleOnAxis();
        final zoomed = scale > 1.01;
        if (zoomed != wasZoomed.value) {
          wasZoomed.value = zoomed;
          zoomedNotifier.value = zoomed;
          onZoomChanged?.call(zoomed);
        }
      }

      transformController.addListener(onTransformChange);
      return () => transformController.removeListener(onTransformChange);
    }, [transformController, zoomedNotifier]);

    useEffect(() => zoomedNotifier.dispose, [zoomedNotifier]);

    // Back while zoomed returns the image to fit-to-screen instead of
    // leaving the viewer, matching the platform photo-viewer model.
    final resetSignal = zoomResetSignal;
    useEffect(() {
      if (resetSignal == null) return null;

      Future<void> resetZoom() async {
        final current = transformController.value.clone();
        if (current.getMaxScaleOnAxis() <= 1.01) return;

        final animation = Matrix4Tween(
          begin: current,
          end: Matrix4.identity(),
        ).animate(zoomAnimator);

        void onAnimating() => transformController.value = animation.value;

        if (zoomAnimator.isCompleted) {
          zoomAnimator.reset();
        }
        animation.addListener(onAnimating);
        await zoomAnimator.forward();
        animation.removeListener(onAnimating);
      }

      resetSignal.addListener(resetZoom);
      return () => resetSignal.removeListener(resetZoom);
    }, [resetSignal, transformController, zoomAnimator]);

    final imageUrl = useMemoized(
      () => contentSetting.loadOriginal ? post.originalFile : post.content.url,
      [post.originalFile, post.content.url, contentSetting.loadOriginal],
    );

    Future<void> handleDoubleTap() async {
      if (zoomAnimator.isAnimating) {
        return;
      }

      final current = transformController.value.clone();
      final currentScale = current.getMaxScaleOnAxis();
      final targetScale = currentScale > 1.01 ? 1.0 : max(2.0, scaleRatio);
      final tap = tapPosition.value;
      final target = targetScale == 1.0
          ? Matrix4.identity()
          : (Matrix4.identity()
              ..translateByDouble(tap.dx, tap.dy, 0, 1)
              ..scaleByDouble(targetScale, targetScale, targetScale, 1)
              ..translateByDouble(-tap.dx, -tap.dy, 0, 1));

      final tween = Matrix4Tween(begin: current, end: target);
      final animation = tween.animate(zoomAnimator);

      void onAnimating() {
        transformController.value = animation.value;
      }

      if (zoomAnimator.isCompleted) {
        zoomAnimator.reset();
      }
      animation.addListener(onAnimating);
      await zoomAnimator.forward();
      animation.removeListener(onAnimating);
    }

    // Pinch-to-zoom precedence over PageView's horizontal swipe.
    //
    // PageView's built-in `HorizontalDragGestureRecognizer` does NOT
    // self-reject on multi-touch (only the single-pointer vertical
    // recognizer below does). So when the user starts a pinch with two
    // fingers, finger 1's slight horizontal motion can claim the arena
    // before [InteractiveViewer]'s [ScaleGestureRecognizer] is given a
    // chance, and the page swipes instead of zooming.
    //
    // The [Listener] tracks active pointer count synchronously at the
    // engine level (Listener observes pointer events regardless of
    // arena outcome). The moment a second pointer lands, we force-fire
    // `onZoomChanged(true)` which flips `controller.canSwipeListenable`
    // to false in the post viewer; the wrapping `ListenableBuilder`
    // rebuilds [PageView] with [NeverScrollableScrollPhysics];
    // [Scrollable] re-runs `_updatePosition()` on `didUpdateWidget`,
    // recreating the position and cancelling any in-flight horizontal
    // drag. The arena is then free for [ScaleGestureRecognizer] to win
    // pinch-zoom uncontested.
    //
    // On the way out (last finger up), if the user did not actually end
    // up zoomed (scale stayed at 1, e.g. a two-finger tap that never
    // resolved into a pinch), we re-enable swipe by firing
    // `onZoomChanged(false)`. If the user IS still zoomed, the
    // [transformController] listener has already kept `wasZoomed` true
    // and we leave swipe disabled.
    void handlePointerDown(PointerDownEvent _) {
      activePointers.value += 1;
      if (activePointers.value == 2 && !wasZoomed.value) {
        onZoomChanged?.call(true);
      }
    }

    void handlePointerLeave(PointerEvent _) {
      activePointers.value = (activePointers.value - 1).clamp(0, 1 << 16);
      if (activePointers.value == 0) {
        final scale = transformController.value.getMaxScaleOnAxis();
        final actuallyZoomed = scale > 1.01;
        if (!actuallyZoomed) {
          onZoomChanged?.call(false);
        }
      }
    }

    return RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: handlePointerDown,
        onPointerUp: handlePointerLeave,
        onPointerCancel: handlePointerLeave,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.passthrough,
          children: [
            Hero(
              tag: post.viewId,
              child: InteractiveViewer(
                transformationController: transformController,
                maxScale: scaleRatio * 5,
                minScale: 1,
                panEnabled: !isBlur.value,
                scaleEnabled: !isBlur.value,
                child: CachedNetworkImage(
                  key: ValueKey(
                    'postImage_${post.viewId}_${contentSetting.loadOriginal}_${retryNonce.value}_${createdAt.value}',
                  ),
                  imageUrl: imageUrl,
                  httpHeaders: headers,
                  fit: BoxFit.contain,
                  memCacheWidth: cacheWidth,
                  memCacheHeight: cacheHeight,
                  imageBuilder: (context, provider) {
                    _scheduleLoadState(
                      loadState,
                      const _PostImageLoadState.completed(),
                    );
                    // ponytail: cacheWidth/cacheHeight live on CachedNetworkImage's
                    // memCacheWidth/memCacheHeight above — the generic Image()
                    // constructor doesn't expose them. The provider from
                    // imageBuilder is already sized by those params.
                    final image = Image(
                      image: provider,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    );
                    return isBlur.value
                        ? ImageFiltered(
                            imageFilter: _kExplicitBlur,
                            child: image,
                          )
                        : image;
                  },
                  progressIndicatorBuilder: (context, url, progress) {
                    _scheduleLoadState(
                      loadState,
                      _PostImageLoadState.loading(progress.progress),
                    );
                    return PostPlaceholderImage(
                      post: post,
                      shouldBlur: isBlur.value,
                      headers: headers,
                    );
                  },
                  errorWidget: (context, url, error) {
                    _scheduleLoadState(
                      loadState,
                      const _PostImageLoadState.failed(),
                    );
                    return PostPlaceholderImage(
                      post: post,
                      shouldBlur: isBlur.value,
                      headers: headers,
                    );
                  },
                ),
              ),
            ),
            // Single-finger gesture overlay. Layered on top of the
            // [InteractiveViewer] using `HitTestBehavior.translucent`, the
            // overlay declares only single-pointer recognizers (tap,
            // double-tap, and conditionally vertical-drag-for-swipe). The
            // moment a second pointer arrives, the custom drag recognizer
            // resolves itself as rejected so [InteractiveViewer]'s
            // [ScaleGestureRecognizer] wins the gesture arena uncontested.
            // This is what makes pinch-to-zoom actually work — the previous
            // wrapping `GestureDetector` with standard `onVerticalDrag*`
            // consistently beat the scale recognizer to the arena.
            //
            // Tap + double-tap are mounted at all times (including while
            // zoomed) so the user can always tap to toggle the overlay or
            // double-tap to zoom back out. The swipe-up / swipe-down
            // recognizer is gated by zoom state so [InteractiveViewer]'s
            // single-finger pan is uncontested while the user is panning a
            // zoomed image.
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: zoomedNotifier,
                builder: (context, isZoomed, _) {
                  return _PostImageGestureOverlay(
                    onTap:
                        onTap ??
                        () {
                          ref.read(fullscreenStateProvider.notifier).toggle();
                        },
                    onDoubleTapDown: (details) {
                      tapPosition.value = details.localPosition;
                    },
                    onDoubleTap: handleDoubleTap,
                    // While zoomed, suppress swipe-up / swipe-down so the
                    // pan recognizer inside [InteractiveViewer] wins
                    // single-finger drags.
                    onSwipeUp: isZoomed ? null : onSwipeUp,
                    onSwipeDown: isZoomed ? null : onSwipeDown,
                  );
                },
              ),
            ),
            if (!isBlur.value)
              Positioned(
                bottom: QuickBar.preferredBottomPosition(context),
                child: _PostMediaStatus(
                  state: loadState.value,
                  onRetry: () {
                    CachedNetworkImage.evictFromCache(imageUrl);
                    retryNonce.value += 1;
                    loadState.value = const _PostImageLoadState.loading(null);
                  },
                ),
              ),
            if (isBlur.value)
              Positioned(
                bottom: QuickBar.preferredBottomPosition(context),
                child: QuickBar.action(
                  title: Text(context.t.unsafeContent),
                  actionTitle: Text(context.t.unblur),
                  onPressed: () {
                    isBlur.value = false;
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Single-pointer gesture surface for the post viewer.
///
/// Owns a custom [SinglePointerVerticalDragRecognizer] that bows out
/// the moment a second pointer is added so [InteractiveViewer]'s
/// [ScaleGestureRecognizer] always wins multi-touch gestures. Tap and
/// double-tap remain single-pointer gestures and coexist via the
/// gesture arena as usual.
class _PostImageGestureOverlay extends StatelessWidget {
  const _PostImageGestureOverlay({
    required this.onTap,
    required this.onDoubleTapDown,
    required this.onDoubleTap,
    required this.onSwipeUp,
    required this.onSwipeDown,
  });

  /// Release velocity (px/s) past which a vertical fling fires the
  /// swipe-up / swipe-down callback. Lowered from 500 in 2.0.12 — the
  /// 500 px/s threshold required an aggressive whip to land; a moderate
  /// flick simply registered as nothing.
  static const double _swipeVelocity = 250;

  final VoidCallback onTap;
  final void Function(TapDownDetails) onDoubleTapDown;
  final VoidCallback onDoubleTap;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (instance) {
                instance.onTap = onTap;
              },
            ),
        DoubleTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
              DoubleTapGestureRecognizer.new,
              (instance) {
                instance
                  ..onDoubleTapDown = onDoubleTapDown
                  ..onDoubleTap = onDoubleTap;
              },
            ),
        if (onSwipeUp != null || onSwipeDown != null)
          SinglePointerVerticalDragRecognizer:
              GestureRecognizerFactoryWithHandlers<
                SinglePointerVerticalDragRecognizer
              >(SinglePointerVerticalDragRecognizer.new, (instance) {
                instance.onEnd = (details) {
                  final velocity = details.velocity.pixelsPerSecond.dy;
                  if (velocity < -_swipeVelocity) {
                    onSwipeUp?.call();
                  } else if (velocity > _swipeVelocity) {
                    onSwipeDown?.call();
                  }
                };
              }),
      },
    );
  }
}

/// A [VerticalDragGestureRecognizer] that synchronously rejects itself
void _scheduleLoadState(
  ValueNotifier<_PostImageLoadState> notifier,
  _PostImageLoadState next,
) {
  if (notifier.value == next) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (notifier.value == next) return;
    notifier.value = next;
  });
}

@immutable
sealed class _PostImageLoadState {
  const _PostImageLoadState();

  const factory _PostImageLoadState.loading(double? progress) =
      _PostImageLoading;
  const factory _PostImageLoadState.completed() = _PostImageCompleted;
  const factory _PostImageLoadState.failed() = _PostImageFailed;
}

class _PostImageLoading extends _PostImageLoadState {
  const _PostImageLoading(this.progress);

  /// Fraction of the download completed, or `null` while the response has no
  /// known total size — an indeterminate load, not a stalled one.
  final double? progress;

  @override
  bool operator ==(Object other) =>
      other is _PostImageLoading && other.progress == progress;

  @override
  int get hashCode => Object.hash(_PostImageLoading, progress);
}

class _PostImageCompleted extends _PostImageLoadState {
  const _PostImageCompleted();

  @override
  bool operator ==(Object other) => other is _PostImageCompleted;

  @override
  int get hashCode => 0;
}

class _PostImageFailed extends _PostImageLoadState {
  const _PostImageFailed();

  @override
  bool operator ==(Object other) => other is _PostImageFailed;

  @override
  int get hashCode => 1;
}

/// Shared error/retry chrome for every media kind. The [AnimatedSwitcher]
/// cross-fades between the three load-state shapes; its child keys stay
/// stable (`completed` / `failed` / `loading`) so a percent tick does not
/// restart the transition.
class _PostMediaStatus extends StatelessWidget {
  const _PostMediaStatus({
    required this.state,
    required this.onRetry,
    this.failedTitle,
  });

  final _PostImageLoadState state;
  final VoidCallback onRetry;

  /// Title shown on the failed state. Defaults to the image copy so the
  /// image path stays byte-for-byte unchanged; video passes its own
  /// `load_video_failed` string.
  final String? failedTitle;

  @override
  Widget build(BuildContext context) {
    // The AnimatedSwitcher's child key only changes between
    // load-state TYPES (loading / completed / failed), NOT on every
    // percent tick. Previously the loading child carried a
    // ValueKey('loading-$loadPercent') which incremented per progress
    // event — the switcher then ran a 200 ms cross-fade for every
    // single percent update, producing the visible blink while a post
    // image was downloading. The pill's percent text and progress
    // value are now updated in-place inside a stable widget instead.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: switch (state) {
        _PostImageCompleted() => const SizedBox.shrink(
          key: ValueKey('completed'),
        ),
        _PostImageFailed() => QuickBar.action(
          key: const ValueKey('failed'),
          title: Text(failedTitle ?? context.t.loadImageFailed),
          actionTitle: Text(context.t.retry),
          onPressed: onRetry,
        ),
        _PostImageLoading(:final progress) => _PostImageLoadingPill(
          key: const ValueKey('loading'),
          progress: progress,
        ),
      },
    );
  }
}

/// Stable loading pill whose percent text + progress value update in
/// place. Living outside [AnimatedSwitcher]'s child-key boundary so
/// the switcher does NOT cross-fade on every percent update.
class _PostImageLoadingPill extends StatelessWidget {
  const _PostImageLoadingPill({super.key, required this.progress});

  /// Fraction completed, or `null` while the response has no known total size.
  /// The pill then spins without a percentage instead of claiming 0%.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    return QuickBar.progress(
      title: progress == null
          ? null
          : Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
      progress: progress,
    );
  }
}

class _PostVideo extends StatefulWidget {
  const _PostVideo({
    required this.post,
    this.onShowDetails,
    this.onSwipeUp,
    this.onSwipeDown,
  });

  final Post post;

  /// Wired by the post viewer to expand the details sheet. Used by both
  /// the new details icon button in the video toolbox and the swipe-up
  /// gesture (when [onSwipeUp] is null and [onShowDetails] is non-null).
  final VoidCallback? onShowDetails;

  /// Single-finger swipe-up (fast fling) handler. The post viewer wires
  /// this to expand the details sheet, mirroring the [_PostImage] gesture
  /// stack.
  final VoidCallback? onSwipeUp;

  /// Single-finger swipe-down (fast fling) handler. The post viewer
  /// wires this to dismiss the route, mirroring the [_PostImage] gesture
  /// stack.
  final VoidCallback? onSwipeDown;

  @override
  State<_PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<_PostVideo> {
  bool _visible = true;
  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey('video_${widget.post.id}_${widget.post.serverId}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        final visible = info.visibleFraction > 0;
        if (visible == _visible) return;
        setState(() {
          _visible = visible;
        });
      },
      child: _PostVideoContent(
        key: ValueKey(
          'video_content_${widget.post.id}_${widget.post.serverId}',
        ),
        post: widget.post,
        onShowDetails: widget.onShowDetails,
        onSwipeUp: widget.onSwipeUp,
        onSwipeDown: widget.onSwipeDown,
        isVisible: _visible,
      ),
    );
  }
}

class _PostVideoContent extends HookConsumerWidget {
  const _PostVideoContent({
    super.key,
    required this.post,
    required this.isVisible,
    this.onShowDetails,
    this.onSwipeUp,
    this.onSwipeDown,
  });

  final Post post;
  final bool isVisible;
  final VoidCallback? onShowDetails;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroMode = context.findAncestorWidgetOfExactType<HeroMode>();
    final isActive = (heroMode?.enabled ?? false) && isVisible;
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final contentSettings = ref.watch(contentSettingStateProvider);
    final fullscreen = ref.watch(fullscreenStateProvider);
    final shouldBlurExplicit =
        contentSettings.blurExplicit && !contentSettings.blurTimelineOnly;
    final shouldBlur = post.rating.isExplicit && shouldBlurExplicit;
    final isBlur = useState(shouldBlur);
    final blurNoticeAnimator = useAnimationController(
      duration: kThemeChangeDuration,
    );
    final showOverlay = useState(true);
    // don't show pause button on initial load
    final showPauseOverlay = useState(false);
    final markMayNeedRebuild = useMarkMayNeedRebuild();
    final isPlaying = useState(true);
    final hideTimer = useState(Timer(const Duration(seconds: 2), () {}));
    final video = useVideoPostSource(ref, post: post, active: isActive);
    final source = video.source;
    final controller = isBlur.value ? null : source.controller;

    onVisibilityChange(bool value) {
      showOverlay.value = value;
      showPauseOverlay.value = value;
    }

    scheduleHide() {
      if (!context.mounted) return;
      hideTimer.value.cancel();
      hideTimer.value = Timer(const Duration(seconds: 2), () {
        if (context.mounted) {
          onVisibilityChange.call(false);
        }
      });
    }

    useEffect(() {
      Future(() {
        if (context.mounted && shouldBlur) {
          blurNoticeAnimator.forward();
        }
      });
    }, []);

    useEffect(() {
      Future<void> initialize() async {
        final player = controller;
        if (player == null) return;

        try {
          await player.initialize();
        } catch (_) {
          // Surface the failure instead of letting it escape as an
          // unhandled async error; the viewer shows a manual retry banner.
          video.reportFailure();
          return;
        }

        void onFirstFrame() {
          player.removeListener(onFirstFrame);
          markMayNeedRebuild();
        }

        player.addListener(onFirstFrame);
        await player.setVolume(contentSettings.videoMuted ? 0 : 1);
        if (isPlaying.value && context.mounted) {
          await player.play();
          scheduleHide();
        }
      }

      initialize();
    }, [controller]);

    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.passthrough,
        children: [
          Hero(
            key: ValueKey(post.viewId),
            tag: post.viewId,
            child: Center(
              child: AspectRatio(
                aspectRatio: post.aspectRatio,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    PostPlaceholderImage(
                      post: post,
                      headers: headers,
                      shouldBlur: isBlur.value,
                    ),
                    if (controller != null) VideoPlayer(controller),
                  ],
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              onVisibilityChange.call(!showOverlay.value);
            },
            child: Container(
              color: showPauseOverlay.value
                  ? Colors.black38
                  : Colors.transparent,
              child: Visibility(
                visible: showOverlay.value,
                replacement: const SizedBox.expand(),
                child: SafeArea(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Visibility(
                        visible: showPauseOverlay.value,
                        child: _PlayPauseOverlay(
                          isPlaying: isPlaying.value,
                          onPressed: () {
                            if (controller != null) {
                              isPlaying.value = !controller.value.isPlaying;
                              controller.value.isPlaying
                                  ? controller.pause()
                                  : controller.play();
                              scheduleHide();
                            } else {
                              isPlaying.value = !isPlaying.value;
                            }
                          },
                        ),
                      ),
                      _ToolboxOverlay(
                        isPlaying: isPlaying.value,
                        source: source,
                        post: post,
                        isMuted: contentSettings.videoMuted,
                        isFullscreen: fullscreen,
                        onAutoHideRequest: scheduleHide,
                        onShowDetails: onShowDetails,
                        onPlayChange: (value) {
                          isPlaying.value = value;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Swipe-up / swipe-down recognizer layered on top of the tap
          // detector. [HitTestBehavior.translucent] lets pointer events
          // also reach the [GestureDetector] above for tap toggling, and
          // tap vs. vertical-drag don't conflict in the gesture arena
          // (tap fires on quick release without movement; drag fires on
          // sufficient vertical motion). Single-pointer-only — multi-
          // touch is rejected so future enhancements that add scale on
          // video are uncontested.
          if (onSwipeUp != null || onSwipeDown != null)
            Positioned.fill(
              child: _PostVideoSwipeOverlay(
                onSwipeUp: onSwipeUp,
                onSwipeDown: onSwipeDown,
              ),
            ),
          if (isBlur.value)
            Positioned(
              bottom: QuickBar.preferredBottomPosition(context) + 24,
              child: QuickBar.action(
                title: Text(context.t.unsafeContent),
                actionTitle: Text(context.t.unblur),
                onPressed: () {
                  isBlur.value = false;
                },
              ),
            ),
          // Playback failure chrome, offset like the blur notice so both
          // sit clear of the bottom toolbox.
          if (!isBlur.value && source.hasError)
            Positioned(
              bottom: QuickBar.preferredBottomPosition(context) + 24,
              child: _PostMediaStatus(
                state: const _PostImageFailed(),
                failedTitle: context.t.loadVideoFailed,
                onRetry: () => unawaited(video.retry()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolboxOverlay extends ConsumerWidget {
  const _ToolboxOverlay({
    required this.post,
    required this.source,
    required this.isPlaying,
    required this.isMuted,
    required this.isFullscreen,
    this.onAutoHideRequest,
    this.onPlayChange,
    this.onShowDetails,
  });

  final bool isPlaying;
  final VideoPostSource source;
  final Post post;
  final bool isMuted;
  final bool isFullscreen;
  final void Function()? onAutoHideRequest;
  final void Function(bool value)? onPlayChange;
  final VoidCallback? onShowDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewPadding = context.mqViewPadding;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        left: viewPadding.left + DesignTokens.spacingSm,
        right: viewPadding.right + DesignTokens.spacingSm,
        bottom: viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onShowDetails != null)
                PostDetailsButton(onPressed: onShowDetails!),
              PostFavoriteButton(
                key: ValueKey('fav_${post.id}_${post.serverId}'),
                post: post,
              ),
              PostDownloadButton(
                key: ValueKey('dl_${post.id}_${post.serverId}'),
                post: post,
              ),
              IconButton(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                tooltip: isMuted
                    ? context.t.viewer.unmute
                    : context.t.viewer.mute,
                onPressed: () async {
                  final mute = await ref
                      .read(contentSettingStateProvider.notifier)
                      .toggleVideoPlayerMute();
                  await source.controller?.setVolume(mute ? 0 : 1);
                },
                icon: Icon(isMuted ? Icons.volume_mute : Icons.volume_up),
              ),
              IconButton(
                color: Colors.white,
                tooltip: isFullscreen
                    ? context.t.viewer.exitFullscreen
                    : context.t.viewer.fullscreen,
                icon: Icon(
                  isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen_outlined,
                ),
                padding: const EdgeInsets.all(16),
                onPressed: () {
                  ref
                      .read(fullscreenStateProvider.notifier)
                      .toggle(shouldLandscape: post.width > post.height);
                  onAutoHideRequest?.call();
                },
              ),
            ],
          ),
          if (!source.hasError) _Progress(source: source),
        ],
      ),
    );
  }
}

/// Velocity-based swipe-up / swipe-down recognizer for the post viewer's
/// video player. Mirrors the [_PostImage] gesture stack: rejects on
/// multi-touch (so future pinch-to-zoom on video would win uncontested),
/// fires only on fast vertical flings (threshold 500 px/s).
class _PostVideoSwipeOverlay extends StatelessWidget {
  const _PostVideoSwipeOverlay({
    required this.onSwipeUp,
    required this.onSwipeDown,
  });

  /// See note in [_PostImageGestureOverlay] — lowered from 500 in 2.0.12
  /// so a moderate flick lands the gesture.
  static const double _swipeVelocity = 250;

  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        SinglePointerVerticalDragRecognizer:
            GestureRecognizerFactoryWithHandlers<
              SinglePointerVerticalDragRecognizer
            >(SinglePointerVerticalDragRecognizer.new, (instance) {
              instance.onEnd = (details) {
                final velocity = details.velocity.pixelsPerSecond.dy;
                if (velocity < -_swipeVelocity) {
                  onSwipeUp?.call();
                } else if (velocity > _swipeVelocity) {
                  onSwipeDown?.call();
                }
              };
            }),
      },
    );
  }
}

class _PlayPauseOverlay extends StatelessWidget {
  const _PlayPauseOverlay({required this.isPlaying, required this.onPressed});

  final bool isPlaying;
  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black38,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: const EdgeInsets.all(8.0),
        color: Colors.white,
        iconSize: 72,
        tooltip: isPlaying ? context.t.viewer.pause : context.t.viewer.play,
        icon: Icon(isPlaying ? Icons.pause_outlined : Icons.play_arrow),
        onPressed: onPressed,
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.source});

  final VideoPostSource source;

  @override
  Widget build(BuildContext context) {
    final controller = source.controller;
    final colorScheme = Theme.of(context).colorScheme;

    if (controller == null || !controller.value.isInitialized) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
        child: LinearProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          backgroundColor: colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
        ),
      );
    }

    return VideoProgressIndicator(
      controller,
      colors: VideoProgressColors(
        playedColor: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.3,
        ),
      ),
      allowScrubbing: true,
      padding: const EdgeInsets.only(top: 16, bottom: 16),
    );
  }
}

class _PostUnknown extends ConsumerWidget {
  const _PostUnknown({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final contentSettings = ref.watch(contentSettingStateProvider);
    final shouldBlurExplicit =
        contentSettings.blurExplicit && !contentSettings.blurTimelineOnly;

    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        Hero(
          tag: post.viewId,
          child: PostPlaceholderImage(
            post: post,
            shouldBlur: shouldBlurExplicit && post.rating.isExplicit,
            headers: headers,
          ),
        ),
        Positioned(
          bottom:
              context.mediaQuery.viewInsets.bottom +
              kBottomNavigationBarHeight +
              32,
          child: QuickBar.action(
            title: Text(
              context.t.unsupportedMedia(fileExt: post.content.url.fileExt),
            ),
            actionTitle: Text(context.t.openExternally),
            onPressed: () {
              if (isSafeUrl(post.originalFile)) {
                launchUrlString(
                  post.originalFile,
                  mode: LaunchMode.externalApplication,
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
