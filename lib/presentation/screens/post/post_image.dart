import 'dart:math';
import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/screens/post/post_placeholder_image.dart';
import 'package:boorusphere/presentation/screens/post/quickbar.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Hoisted out of `build` so we don't allocate one [ImageFilter] per
/// repaint while the user is zooming or scrolling.
final ImageFilter _kExplicitBlur = ImageFilter.blur(
  sigmaX: 5,
  sigmaY: 5,
  tileMode: TileMode.decal,
);

class PostImage extends HookConsumerWidget {
  const PostImage({
    super.key,
    required this.post,
    this.onZoomChanged,
    this.onTap,
    this.onSwipeUp,
    this.onSwipeDown,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentSetting = ref.watch(contentSettingStateProvider);
    final shouldBlurExplicit =
        contentSetting.blurExplicit && !contentSetting.blurTimelineOnly;
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final isBlur = useState(post.rating.isExplicit && shouldBlurExplicit);
    final transformController = useTransformationController();
    final zoomAnimator = useAnimationController(
      duration: const Duration(milliseconds: 150),
    );
    final wasZoomed = useRef(false);
    final activePointers = useRef(0);
    final tapPosition = useRef(Offset.zero);
    final retryNonce = useState(0);
    final createdAt = useState(DateTime.now().millisecondsSinceEpoch);
    final loadState = useState<_PostImageLoadState>(
      const _PostImageLoadState.loading(0),
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
          onZoomChanged?.call(zoomed);
        }
      }

      transformController.addListener(onTransformChange);
      return () => transformController.removeListener(onTransformChange);
    }, [transformController]);

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
                      _PostImageLoadState.loading(progress.progress ?? 0),
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
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: transformController,
                builder: (context, matrix, _) {
                  final scale = matrix.getMaxScaleOnAxis();
                  final isZoomed = scale > 1.01;
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
                child: _PostImageStatus(
                  state: loadState.value,
                  onRetry: () {
                    CachedNetworkImage.evictFromCache(imageUrl);
                    retryNonce.value += 1;
                    loadState.value = const _PostImageLoadState.loading(0);
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
/// Owns a custom [_SinglePointerVerticalDragRecognizer] that bows out
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
          _SinglePointerVerticalDragRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _SinglePointerVerticalDragRecognizer
              >(_SinglePointerVerticalDragRecognizer.new, (instance) {
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
/// the moment a second pointer joins the gesture, freeing the gesture
/// arena for [InteractiveViewer]'s [ScaleGestureRecognizer] to win
/// pinch gestures uncontested.
///
/// The default [VerticalDragGestureRecognizer] tracks all incoming
/// pointers and decides whether to claim based on dominant motion —
/// which can race with scale recognition during a pinch that includes
/// any vertical component, leaving the user unable to zoom.
class _SinglePointerVerticalDragRecognizer
    extends VerticalDragGestureRecognizer {
  _SinglePointerVerticalDragRecognizer();

  final Set<int> _activePointers = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      // Multi-touch — yield to [InteractiveViewer]'s scale recognizer.
      //
      // We deliberately do NOT call `super.addAllowedPointer(event)`
      // for this 2nd+ pointer — we don't want to track its drag. But
      // because we never tracked it, Flutter never routes its
      // up/cancel events to us, and `rejectGesture(pointer)` /
      // `didStopTrackingLastPointer(pointer)` are NEVER fired for this
      // pointer either. If we leave [event.pointer] in [_activePointers]
      // it leaks: the next pointer-down event we see will count it
      // toward the multi-touch threshold even though the finger is
      // long gone, and the recognizer will silently self-reject every
      // subsequent single-finger gesture.
      //
      // User report (post v2.0.15): "after zooming out using pinch
      // until original size, if I zoom out again at original size, the
      // swipe up and down gesture is doing nothing." Reproduces because
      // a second pinch at scale = 1 doesn't toggle `isZoomed`, so
      // [RawGestureDetector] keeps the same recognizer instance with
      // the leaked pointer ID.
      //
      // Fix: explicitly remove the new pointer from our local set
      // before resolving. Pointer 1 (the one in arena) gets cleaned up
      // via `rejectGesture` / `didStopTrackingLastPointer` as usual.
      _activePointers.remove(event.pointer);
      resolve(GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
  }

  @override
  void rejectGesture(int pointer) {
    _activePointers.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _activePointers.remove(pointer);
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  String get debugDescription => 'single_pointer_vertical_drag';
}

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

  const factory _PostImageLoadState.loading(double progress) =
      _PostImageLoading;
  const factory _PostImageLoadState.completed() = _PostImageCompleted;
  const factory _PostImageLoadState.failed() = _PostImageFailed;
}

class _PostImageLoading extends _PostImageLoadState {
  const _PostImageLoading(this.progress);

  final double progress;

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

class _PostImageStatus extends StatelessWidget {
  const _PostImageStatus({required this.state, required this.onRetry});

  final _PostImageLoadState state;
  final VoidCallback onRetry;

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
          title: Text(context.t.loadImageFailed),
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

  final double progress;

  @override
  Widget build(BuildContext context) {
    final loadPercent = (progress * 100).round();
    return QuickBar.progress(
      title: Text(
        '$loadPercent%',
        style: const TextStyle(fontWeight: FontWeight.w400),
      ),
      progress: loadPercent / 100,
    );
  }
}
