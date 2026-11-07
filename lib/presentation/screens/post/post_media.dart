import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_lock/app_lock_state.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/screens/post/hooks/video_post.dart';
import 'package:boorusphere/presentation/screens/post/post_placeholder_image.dart';
import 'package:boorusphere/presentation/screens/post/post_toolbox.dart';
import 'package:boorusphere/presentation/screens/post/quickbar.dart';
import 'package:boorusphere/presentation/theme/app_media_chrome.dart';
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
    this.isRouteVisible = true,
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

  /// Whether the route showing this media is the one on screen. A video runs
  /// on a platform surface rather than a Flutter ticker, so covering the
  /// route does not silence it on its own; the video renderer pauses when
  /// this turns false. Ignored by non-video kinds.
  final bool isRouteVisible;

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
        isRouteVisible: isRouteVisible,
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

/// How long the video chrome waits for the platform to answer `initialize`
/// before it admits this post is not going to play. A platform that accepts
/// the request and then stays silent never throws, so without a bound the
/// loader has no terminal state and no retry to offer.
const Duration _kVideoSetupTimeout = Duration(seconds: 30);

/// The same bound for the image download, which has no timeout of its own.
/// Every received byte re-arms it, so it only fires on a connection that went
/// quiet — never on a large file moving slowly.
const Duration _kImageStallTimeout = Duration(seconds: 30);

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
    final headers = ref.watch(
      postHeadersFactoryProvider(postHeadersKeyOf(post)),
    );
    final isBlur = useState(post.rating.isExplicit && shouldBlurExplicit);
    final transformController = useTransformationController();
    final zoomAnimator = useAnimationController(
      duration: context.motionDuration(DesignTokens.durationFast),
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
    // Only the status pill reads the load state, so it lives in a notifier:
    // rebuilding the zoomable image subtree on every progress tick is wasted
    // work while a large sample downloads.
    final loadState = useMemoized(
      () => ValueNotifier<_PostImageLoadState>(
        const _PostImageLoadState.loading(null),
      ),
    );
    useEffect(() => loadState.dispose, [loadState]);

    final deviceRatio = MediaQuery.sizeOf(context).aspectRatio;
    final imageRatio = post.aspectRatio;
    final scaleRatio = deviceRatio < imageRatio
        ? imageRatio / deviceRatio
        : deviceRatio / imageRatio;

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
        if (current.getMaxScaleOnAxis() <= 1.01) {
          // The viewer-side claim can outlive this page's transform: a page
          // change clears it while a listener reset is still pending. This
          // image is already at fit-to-screen, so no transform event is coming
          // to report that; say so here, or Back would stay consumed by a zoom
          // that is not showing.
          onZoomChanged?.call(false);
          return;
        }

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

    // The load state is only about the resource it last reported, so a new URL
    // must not inherit the previous one's verdict.
    //
    // A request that stops answering never becomes a failure on its own — a
    // server can hold the connection open and send nothing — so the watch gives
    // the pill a terminal state to fall back to. Every received byte re-arms it,
    // which means only silence trips it, never a large file moving slowly.
    //
    // `firstFrameSeen` ends the loading phase for good. Once the image is on
    // screen, the network widget keeps calling the progress builder to fade its
    // own indicator out — and for an animated image it does so once per frame,
    // because every frame is a rebuild. Those calls carry no real progress, so
    // without the latch they re-open `loading` on top of a fully painted post.
    final stallTimer = useRef<Timer?>(null);
    final firstFrameSeen = useRef(false);
    void armStallWatch() {
      stallTimer.value?.cancel();
      stallTimer.value = Timer(_kImageStallTimeout, () {
        if (loadState.value case _PostImageLoading()) {
          loadState.value = const _PostImageLoadState.failed();
        }
      });
    }

    void beginLoad() {
      firstFrameSeen.value = false;
      loadState.value = const _PostImageLoadState.loading(null);
      armStallWatch();
    }

    useEffect(() {
      beginLoad();
      return () => stallTimer.value?.cancel();
    }, [imageUrl]);

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
                // The image is the screen's content; without a label the only
                // thing a screen reader found here was the chrome around it.
                child: Semantics(
                  image: true,
                  label: post.describeTags.isEmpty
                      ? '#${post.id}'
                      : post.describeTags,
                  child: CachedNetworkImage(
                    key: ValueKey(
                      'postImage_${post.viewId}_${contentSetting.loadOriginal}_${retryNonce.value}_${createdAt.value}',
                    ),
                    imageUrl: imageUrl,
                    httpHeaders: headers,
                    fit: BoxFit.contain,
                    imageBuilder: (context, provider) {
                      stallTimer.value?.cancel();
                      firstFrameSeen.value = true;
                      _scheduleLoadState(
                        loadState,
                        const _PostImageLoadState.completed(),
                      );
                      // The network widget builds its own image from the same
                      // provider object handed to this builder, so both resolve
                      // to one cache entry and one decode. Sizing that internal
                      // image (`memCacheWidth`/`memCacheHeight`) would put it
                      // behind a different key: a second, wasted decode of the
                      // same bytes. This one stays at the file's resolution
                      // because `InteractiveViewer` can scale past the screen.
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
                      // Only the real download phase reaches here: once a frame
                      // has been painted, later calls are the fade-out pass.
                      if (!firstFrameSeen.value) {
                        // Bytes moved, so the watch starts again from now.
                        armStallWatch();
                        _scheduleLoadState(
                          loadState,
                          _PostImageLoadState.loading(progress.progress),
                        );
                      }
                      return PostPlaceholderImage(
                        post: post,
                        shouldBlur: isBlur.value,
                        headers: headers,
                      );
                    },
                    errorWidget: (context, url, error) {
                      stallTimer.value?.cancel();
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
            ),
            // Single-finger gesture overlay. Layered on top of the
            // [InteractiveViewer] using `HitTestBehavior.translucent`, the
            // overlay declares only single-pointer recognizers (tap,
            // double-tap, and conditionally vertical-drag-for-swipe). The
            // moment a second pointer arrives, the custom drag recognizer
            // resolves itself as rejected so [InteractiveViewer]'s
            // [ScaleGestureRecognizer] wins the gesture arena uncontested.
            // This is what makes pinch-to-zoom actually work; the previous
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
            // The status chrome stays mounted while blurred: a blurred post is
            // still downloading its real image, and a load that failed has to
            // offer retry without making the user unblur the artwork first to
            // reach the button. Only the progress pill yields, because it would
            // sit on top of the unblur pill.
            Positioned(
              bottom:
                  QuickBar.preferredBottomPosition(context) +
                  (isBlur.value ? DesignTokens.controlHeightMin : 0),
              child: ValueListenableBuilder<_PostImageLoadState>(
                valueListenable: loadState,
                builder: (context, state, _) => _PostMediaStatus(
                  state: state,
                  hideProgress: isBlur.value,
                  onRetry: () {
                    CachedNetworkImage.evictFromCache(imageUrl);
                    retryNonce.value += 1;
                    // The retry key changes but `imageUrl` does not, so the URL
                    // effect will not re-open the loading phase; do it here or
                    // the new attempt would run without a pill or a watchdog.
                    beginLoad();
                  },
                ),
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
  /// swipe-up / swipe-down callback. Lowered from 500 in 2.0.12; the
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
  /// known total size: an indeterminate load, not a stalled one.
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
    this.hideProgress = false,
  });

  final _PostImageLoadState state;
  final VoidCallback onRetry;

  /// Title shown on the failed state. Defaults to the image copy so the
  /// image path stays byte-for-byte unchanged; video passes its own
  /// `load_video_failed` string.
  final String? failedTitle;

  /// Suppresses the progress pill. A blurred post shows its own action pill in
  /// the same slot, so only the failure — the thing the user cannot otherwise
  /// reach — is worth rendering on top of it.
  final bool hideProgress;

  @override
  Widget build(BuildContext context) {
    // The AnimatedSwitcher's child key only changes between
    // load-state TYPES (loading / completed / failed), NOT on every
    // percent tick. Previously the loading child carried a
    // ValueKey('loading-$loadPercent') which incremented per progress
    // event; the switcher then ran a 200 ms cross-fade for every
    // single percent update, producing the visible blink while a post
    // image was downloading. The pill's percent text and progress
    // value are now updated in-place inside a stable widget instead.
    return AnimatedSwitcher(
      duration: context.motionDuration(DesignTokens.durationFast),
      switchInCurve: DesignTokens.curveDecelerate,
      switchOutCurve: DesignTokens.curveAccelerate,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: switch (state) {
        _PostImageCompleted() || _PostImageLoading() when hideProgress =>
          const SizedBox.shrink(key: ValueKey('idle')),
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
    // The pill used to read as a bare "47%", a number with no subject, and it
    // asked for weight 400 inline, which is what the role already carries. The
    // label now names what is loading; the visible text keeps its own role.
    //
    // With no percentage to show there is no text at all, and a ring carries
    // nothing a screen reader can say — so the label moves onto the pill.
    final pill = QuickBar.progress(
      title: progress == null
          ? null
          : Semantics(
              label: '${context.t.loadingMedia} ${(progress * 100).round()}%',
              child: Text('${(progress * 100).round()}%'),
            ),
      progress: progress,
    );

    return progress == null
        ? Semantics(label: context.t.loadingMedia, child: pill)
        : pill;
  }
}

class _PostVideo extends StatefulWidget {
  const _PostVideo({
    required this.post,
    this.onShowDetails,
    this.onSwipeUp,
    this.onSwipeDown,
    this.isRouteVisible = true,
  });

  final Post post;

  /// Whether the viewer's route is the one on screen.
  final bool isRouteVisible;

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
        isRouteVisible: widget.isRouteVisible,
      ),
    );
  }
}

class _PostVideoContent extends HookConsumerWidget {
  const _PostVideoContent({
    super.key,
    required this.post,
    required this.isVisible,
    this.isRouteVisible = true,
    this.onShowDetails,
    this.onSwipeUp,
    this.onSwipeDown,
  });

  final Post post;
  final bool isVisible;

  /// Whether the viewer's route is the one on screen.
  final bool isRouteVisible;
  final VoidCallback? onShowDetails;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroMode = context.findAncestorWidgetOfExactType<HeroMode>();
    // The lock cover is a shell sibling, not a route, so isRouteVisible stays
    // true beneath it. A video under the gate has to release its player —
    // audio and decoder both — which is what active gates, not merely pause.
    final locked = ref.watch(appLockProvider.select((it) => it.isLocked));
    final isActive = (heroMode?.enabled ?? false) && isVisible && !locked;
    final headers = ref.watch(
      postHeadersFactoryProvider(postHeadersKeyOf(post)),
    );
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
    final hideTimer = useRef<Timer?>(null);
    final video = useVideoPostSource(ref, post: post, active: isActive);
    final source = video.source;
    final controller = isBlur.value ? null : source.controller;
    final seekSeconds = contentSettings.videoSeekSeconds.clamp(2, 15).toInt();
    final feedback = useState<_VideoGestureHint?>(null);
    final feedbackTimer = useRef<Timer?>(null);
    final doubleTapPosition = useRef(Offset.zero);
    // Read by the initialize continuation, which must not start playback on a
    // viewer that has since been covered.
    final routeVisibleRef = useRef(isRouteVisible);
    routeVisibleRef.value = isRouteVisible;

    // Both timers are page-owned: a pending auto-hide left running past the
    // page's death is a leak the test framework can only forgive by pumping
    // the clock until it fires.
    useEffect(
      () => () {
        feedbackTimer.value?.cancel();
        hideTimer.value?.cancel();
      },
      [],
    );

    onVisibilityChange(bool value) {
      showOverlay.value = value;
      showPauseOverlay.value = value;
    }

    // Hiding the toolbox assumes the viewer can tap the picture to bring it
    // back. Under TalkBack, or with animations removed, that tap is not
    // discoverable, so the controls stay up instead of timing out.
    final keepControlsVisible =
        context.reducedMotion ||
        (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);

    scheduleHide() {
      if (!context.mounted) return;
      hideTimer.value?.cancel();
      if (keepControlsVisible) return;
      hideTimer.value = Timer(const Duration(seconds: 2), () {
        if (context.mounted) {
          onVisibilityChange.call(false);
        }
      });
    }

    void showFeedback(_VideoGestureHint hint) {
      feedback.value = hint;
      feedbackTimer.value?.cancel();
      feedbackTimer.value = Timer(const Duration(milliseconds: 650), () {
        if (context.mounted) feedback.value = null;
      });
    }

    void togglePlayback() {
      final player = controller;
      if (player == null) {
        isPlaying.value = !isPlaying.value;
        return;
      }
      isPlaying.value = !player.value.isPlaying;
      player.value.isPlaying ? player.pause() : player.play();
      scheduleHide();
    }

    void seekRelative(Duration delta) {
      final player = controller;
      if (player == null || !player.value.isInitialized) return;

      final duration = player.value.duration;
      final target = player.value.position + delta;
      final clamped = target < Duration.zero
          ? Duration.zero
          : (target > duration ? duration : target);
      player.seekTo(clamped);
      scheduleHide();
    }

    void handleDoubleTap() {
      if (isBlur.value) return;

      final player = controller;
      if (player == null) return;

      // The seek zones are the familiar left / centre / right thirds. A
      // double-tap on an image still belongs to the zoom gesture there; this
      // surface only ever owns video posts.
      final width = context.size?.width ?? MediaQuery.sizeOf(context).width;
      final dx = doubleTapPosition.value.dx;
      final step = Duration(seconds: seekSeconds);

      if (dx < width / 3) {
        seekRelative(-step);
        showFeedback(
          _VideoGestureHint(Icons.fast_rewind, '-${step.inSeconds}s'),
        );
      } else if (dx > width * 2 / 3) {
        seekRelative(step);
        showFeedback(
          _VideoGestureHint(Icons.fast_forward, '+${step.inSeconds}s'),
        );
      } else {
        togglePlayback();
        showFeedback(
          _VideoGestureHint(isPlaying.value ? Icons.play_arrow : Icons.pause),
        );
      }
    }

    useEffect(() {
      Future(() {
        if (context.mounted && shouldBlur) {
          blurNoticeAnimator.forward();
        }
      });
    }, []);

    // A platform video surface keeps playing on its own when the Flutter tree
    // above it is covered, so a related timeline pushed over the viewer used
    // to keep the old video talking underneath it. Pause while the viewer is
    // not on screen, and resume only a playback the user was actually
    // watching when it got covered.
    final resumeOnShow = useRef(false);
    useEffect(() {
      final player = controller;
      if (player == null) return null;

      if (!isRouteVisible) {
        resumeOnShow.value = isPlaying.value;
        if (player.value.isPlaying) {
          unawaited(player.pause());
        }
        return null;
      }

      if (resumeOnShow.value) {
        resumeOnShow.value = false;
        if (player.value.isInitialized) {
          unawaited(player.play());
        }
      }
      return null;
    }, [isRouteVisible, controller]);

    useEffect(() {
      final player = controller;
      if (player == null) return null;

      // The effect can outlive its controller: a page change, a retry or the
      // viewer closing disposes the player while `initialize` is still
      // waiting on the platform. Every step after an await checks this flag,
      // so a dropped player is neither reported as a failure nor played into.
      var cancelled = false;
      // True until setup finishes, so the intent to autoplay is not overwritten
      // by a plugin that has not been told to play yet.
      var settingUp = true;

      // The controller's own value is the only place a failure that arrives
      // after setup shows up: `initialize` completes on the platform's
      // `initialized` event, so anything the plugin reports later cannot reach
      // the catch below. Listening for the whole life of the controller is what
      // gives the loading chrome a terminal state, keeps the play/pause
      // affordance honest when the plugin pauses on its own (backgrounding
      // does), and lets a player that answers after the timeout take its
      // failure back.
      //
      // The player also notifies ten times a second while it runs, so only the
      // facts the chrome draws from are allowed to dirty it. The playhead label
      // belongs to the plugin's own indicator, not to this page's rebuild rate.
      var sawError = player.value.hasError;
      var sawReady = player.value.isInitialized;
      var sawPlaying = player.value.isPlaying;

      void onPlayerValue() {
        if (cancelled) return;

        final value = player.value;
        final chromeChanged =
            value.hasError != sawError ||
            value.isInitialized != sawReady ||
            value.isPlaying != sawPlaying;
        sawError = value.hasError;
        sawReady = value.isInitialized;
        sawPlaying = value.isPlaying;

        if (value.hasError) {
          // An errored player is not playing, whatever the intent said. Left
          // alone, the pause glyph would keep claiming playback that stopped.
          isPlaying.value = false;
          video.reportFailure();
          return;
        }

        if (value.isInitialized) {
          video.reportReady();
          // While setting up, `isPlaying` carries the intent to autoplay; the
          // plugin has not been told to play yet, so its answer is not a fact.
          if (!settingUp) isPlaying.value = value.isPlaying;
        }

        if (chromeChanged) markMayNeedRebuild();
      }

      Future<void> initialize() async {
        // The controller is recreated only when this post becomes active
        // again, so a new visit autoplays even if the previous one was paused.
        isPlaying.value = true;

        try {
          // Nothing else bounds this wait: a platform that accepts the request
          // and stays silent would hold the toolbox open on a loader forever.
          await player.initialize().timeout(_kVideoSetupTimeout);
          if (cancelled) return;

          await player.setVolume(contentSettings.videoMuted ? 0 : 1);
          if (cancelled) return;

          // Starting here would put audio on another page if the viewer was
          // covered while the player initialized; the visibility effect above
          // resumes playback when the viewer comes back.
          if (isPlaying.value && context.mounted && routeVisibleRef.value) {
            await player.play();
            if (cancelled) return;
            scheduleHide();
          }
        } catch (_) {
          // Surface the failure instead of letting it escape as an
          // unhandled async error; the viewer shows a manual retry banner.
          // A player dropped mid-setup is not a failure.
          if (!cancelled) video.reportFailure();
        } finally {
          settingUp = false;
        }
      }

      player.addListener(onPlayerValue);
      unawaited(initialize());
      return () {
        cancelled = true;
        player.removeListener(onPlayerValue);
      };
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
            onDoubleTapDown: (details) {
              doubleTapPosition.value = details.localPosition;
            },
            onDoubleTap: handleDoubleTap,
            child: Container(
              color: showPauseOverlay.value
                  ? AppMediaChrome.of(context).scrimSoft
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
                          onPressed: togglePlayback,
                        ),
                      ),
                      _ToolboxOverlay(
                        isPlaying: isPlaying.value,
                        controller: controller,
                        hasError: source.hasError,
                        // A blurred post has no playback to report progress
                        // for: its player is deliberately withheld, so the row
                        // would claim a load that can never finish.
                        showProgress: !isBlur.value,
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
          // sufficient vertical motion). Single-pointer-only, multi-
          // touch is rejected so future enhancements that add scale on
          // video are uncontested.
          if (onSwipeUp != null || onSwipeDown != null)
            Positioned.fill(
              child: _PostVideoSwipeOverlay(
                onSwipeUp: onSwipeUp,
                onSwipeDown: onSwipeDown,
              ),
            ),
          // Double-tap feedback: a brief, non-interactive echo of the action
          // so a seek is visible even when the toolbox is hidden.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedSwitcher(
                  duration: context.motionDuration(DesignTokens.durationFast),
                  child: feedback.value == null
                      ? const SizedBox.shrink(
                          key: ValueKey('video_feedback_hidden'),
                        )
                      : _VideoGestureFeedback(
                          key: ValueKey(
                            'video_feedback_${feedback.value!.icon.codePoint}'
                            '_${feedback.value!.label}',
                          ),
                          hint: feedback.value!,
                        ),
                ),
              ),
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
    required this.controller,
    required this.hasError,
    required this.showProgress,
    required this.isPlaying,
    required this.isMuted,
    required this.isFullscreen,
    this.onAutoHideRequest,
    this.onPlayChange,
    this.onShowDetails,
  });

  final bool isPlaying;

  /// The player this overlay may talk to: null while the post is blurred or the
  /// source has not produced a controller yet.
  final VideoPlayerController? controller;

  /// Playback is known to be dead, so the progress row is replaced by the
  /// viewer's retry banner.
  final bool hasError;

  /// Whether there is a load to report. False for a blurred post, whose player
  /// is withheld on purpose: an indeterminate bar there would claim a load that
  /// can never finish.
  final bool showProgress;

  final Post post;
  final bool isMuted;
  final bool isFullscreen;
  final void Function()? onAutoHideRequest;
  final void Function(bool value)? onPlayChange;
  final VoidCallback? onShowDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewPadding = context.mqViewPadding;
    final chrome = AppMediaChrome.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [chrome.scrim, Colors.transparent],
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
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                color: chrome.foreground,
                tooltip: isMuted
                    ? context.t.viewer.unmute
                    : context.t.viewer.mute,
                onPressed: () async {
                  final mute = await ref
                      .read(contentSettingStateProvider.notifier)
                      .toggleVideoPlayerMute();
                  await controller?.setVolume(mute ? 0 : 1);
                },
                icon: Icon(isMuted ? Icons.volume_mute : Icons.volume_up),
              ),
              IconButton(
                color: chrome.foreground,
                tooltip: isFullscreen
                    ? context.t.viewer.exitFullscreen
                    : context.t.viewer.fullscreen,
                icon: Icon(
                  isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen_outlined,
                ),
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                onPressed: () {
                  ref
                      .read(fullscreenStateProvider.notifier)
                      .toggle(shouldLandscape: post.width > post.height);
                  onAutoHideRequest?.call();
                },
              ),
            ],
          ),
          if (showProgress && !hasError) _Progress(controller: controller),
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

  /// See note in [_PostImageGestureOverlay], lowered from 500 in 2.0.12
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

@immutable
class _VideoGestureHint {
  const _VideoGestureHint(this.icon, [this.label]);

  final IconData icon;

  /// Null for the play/pause echo, which reads better as an icon alone.
  final String? label;
}

class _VideoGestureFeedback extends StatelessWidget {
  const _VideoGestureFeedback({super.key, required this.hint});

  final _VideoGestureHint hint;

  @override
  Widget build(BuildContext context) {
    final label = hint.label;
    final chrome = AppMediaChrome.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: chrome.scrim,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingLg,
          vertical: DesignTokens.spacingSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hint.icon,
              color: chrome.foreground,
              size: DesignTokens.iconAction,
            ),
            if (label != null) ...[
              const SizedBox(width: DesignTokens.spacingSm),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: chrome.foreground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayPauseOverlay extends StatelessWidget {
  const _PlayPauseOverlay({required this.isPlaying, required this.onPressed});

  final bool isPlaying;
  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final chrome = AppMediaChrome.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chrome.scrimSoft,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: const EdgeInsets.all(8.0),
        color: chrome.foreground,
        iconSize: 72,
        tooltip: isPlaying ? context.t.viewer.pause : context.t.viewer.play,
        icon: Icon(isPlaying ? Icons.pause_outlined : Icons.play_arrow),
        onPressed: onPressed,
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.controller});

  /// How far a screen-reader adjust step moves the playhead.
  static const _seekStep = Duration(seconds: 5);

  /// The player to read progress from, or null while the source has not
  /// produced one yet. Both cases are drawn as a load in progress.
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    final colorScheme = Theme.of(context).colorScheme;
    final chrome = AppMediaChrome.of(context);

    if (controller == null || !controller.value.isInitialized) {
      // The bar is the only thing saying anything is happening, and a ring
      // with no label says nothing to a screen reader at all.
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
        child: Semantics(
          label: context.t.loadingMedia,
          child: LinearProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            backgroundColor: chrome.track,
          ),
        ),
      );
    }

    final value = controller.value;
    final duration = value.duration;
    final position = value.position;

    String clock(Duration time) {
      final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '${time.inMinutes}:$seconds';
    }

    Duration clamp(Duration time) {
      if (time < Duration.zero) return Duration.zero;
      if (time > duration) return duration;
      return time;
    }

    void seek(Duration time) {
      if (duration <= Duration.zero) return;
      controller.seekTo(clamp(time));
    }

    // The bar is a thin drag target. A slider node gives TalkBack and switch
    // access a way to read the playhead and move it without aiming at it.
    return Semantics(
      slider: true,
      label: context.t.videoPosition,
      value: '${clock(position)} / ${clock(duration)}',
      increasedValue: clock(clamp(position + _seekStep)),
      decreasedValue: clock(clamp(position - _seekStep)),
      onIncrease: duration > Duration.zero
          ? () => seek(position + _seekStep)
          : null,
      onDecrease: duration > Duration.zero
          ? () => seek(position - _seekStep)
          : null,
      child: VideoProgressIndicator(
        controller,
        colors: VideoProgressColors(
          playedColor: colorScheme.primary,
          backgroundColor: chrome.track,
        ),
        allowScrubbing: true,
        padding: const EdgeInsets.only(top: 16, bottom: 16),
      ),
    );
  }
}

class _PostUnknown extends ConsumerWidget {
  const _PostUnknown({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(
      postHeadersFactoryProvider(postHeadersKeyOf(post)),
    );
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
          // The guard decides whether the action exists at all: an address the
          // app will not open used to leave a button that swallowed the tap.
          child: isSafeUrl(post.originalFile)
              ? QuickBar.action(
                  title: Text(
                    context.t.unsupportedMedia(
                      fileExt: post.content.url.fileExt,
                    ),
                  ),
                  actionTitle: Text(context.t.openExternally),
                  onPressed: () => launchUrlString(
                    post.originalFile,
                    mode: LaunchMode.externalApplication,
                  ),
                )
              : QuickBar(
                  title: Text(
                    context.t.unsupportedMedia(
                      fileExt: post.content.url.fileExt,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
