import 'dart:math';
import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/screens/post/post_placeholder_image.dart';
import 'package:boorusphere/presentation/screens/post/quickbar.dart';
import 'package:boorusphere/presentation/utils/extensions/images.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/utils/extensions/number.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Hoisted out of `build` so we don't allocate one [ImageFilter] per
/// repaint while the user is zooming or scrolling. Reused by [PostImage]
/// and the placeholder render path.
final ImageFilter _kExplicitBlur =
    ImageFilter.blur(sigmaX: 5, sigmaY: 5, tileMode: TileMode.decal);

class PostImage extends HookConsumerWidget {
  const PostImage({
    super.key,
    required this.post,
    this.onZoomChanged,
  });

  final Post post;

  /// Called whenever the rendered image transitions between resting (scale
  /// == 1) and zoomed-in (scale > 1) states. Used by the post viewer to
  /// disable page-swipe gestures while a zoom is active so panning a
  /// zoomed image does not accidentally swipe to the next post.
  final void Function(bool isZoomed)? onZoomChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentSetting = ref.watch(contentSettingStateProvider);
    final shouldBlurExplicit =
        contentSetting.blurExplicit && !contentSetting.blurTimelineOnly;
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final isBlur = useState(post.rating.isExplicit && shouldBlurExplicit);
    final zoomAnimator =
        useAnimationController(duration: const Duration(milliseconds: 150));
    final imageLoadState = useStreamController<ExtendedImageState>();
    // Tracks whether we have already notified the parent that the image is
    // zoomed in. We only fire when the boolean transitions, not on every
    // gesture detail tick.
    final wasZoomed = useRef(false);

    useEffect(() {
      if (post.rating != BooruRating.explicit || !shouldBlurExplicit) {
        return null;
      }
      return null;
    }, const []);

    final deviceRatio = MediaQuery.sizeOf(context).aspectRatio;
    final imageRatio = post.aspectRatio;
    final scaleRatio = deviceRatio < imageRatio
        ? imageRatio / deviceRatio
        : deviceRatio / imageRatio;

    return GestureDetector(
      onTap: () {
        ref.read(fullscreenStateProvider.notifier).toggle();
      },
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.passthrough,
          children: [
            Hero(
              tag: post.viewId,
              child: ExtendedImage.network(
                contentSetting.loadOriginal
                    ? post.originalFile
                    : post.content.url,
                headers: headers,
                fit: BoxFit.contain,
                mode: isBlur.value
                    ? ExtendedImageMode.none
                    : ExtendedImageMode.gesture,
                initGestureConfigHandler: (state) {
                  return GestureConfig(
                    maxScale: scaleRatio * 5,
                    inPageView: true,
                    gestureDetailsIsChanged: (details) {
                      // Treat anything strictly above the resting scale as
                      // "zoomed". A small epsilon avoids flapping on the
                      // double-tap animation overshoot.
                      final scale = details?.totalScale ?? 1;
                      final zoomed = scale > 1.01;
                      if (zoomed != wasZoomed.value) {
                        wasZoomed.value = zoomed;
                        onZoomChanged?.call(zoomed);
                      }
                    },
                  );
                },
                handleLoadingProgress: true,
                beforePaintImage: (canvas, rect, image, paint) {
                  if (isBlur.value) {
                    paint.imageFilter = _kExplicitBlur;
                  }
                  return false;
                },
                loadStateChanged: (state) {
                  imageLoadState.add(state);

                  return state.isCompleted
                      ? state.completedWidget
                      : PostPlaceholderImage(
                          post: post,
                          shouldBlur: isBlur.value,
                          headers: headers,
                        );
                },
                onDoubleTap: (state) async {
                  if (zoomAnimator.isAnimating) {
                    // It should be impossible for human to do quadruple-tap
                    // at 150 ms. Still, better than no guards at all
                    return;
                  }

                  final downOffset = state.pointerDownPosition;
                  final begin = state.gestureDetails?.totalScale ?? 1;
                  final animation = zoomAnimator.drive(
                    Tween<double>(
                      begin: begin,
                      end: begin == 1 ? max(2, scaleRatio) : 1.0,
                    ),
                  );

                  void onAnimating() {
                    state.handleDoubleTap(
                        scale: animation.value, doubleTapPosition: downOffset);
                  }

                  if (zoomAnimator.isCompleted) {
                    zoomAnimator.reset();
                  }
                  animation.addListener(onAnimating);
                  await zoomAnimator.forward();
                  animation.removeListener(onAnimating);
                },
              ),
            ),
            if (!isBlur.value)
              Positioned(
                bottom: QuickBar.preferredBottomPosition(context),
                child: StreamBuilder(
                  stream: imageLoadState.stream,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    if (data is ExtendedImageState) {
                      return _PostImageStatus(state: data);
                    } else {
                      return const SizedBox.shrink();
                    }
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

class _PostImageStatus extends StatelessWidget {
  const _PostImageStatus({
    required this.state,
  });

  final ExtendedImageState state;

  @override
  Widget build(BuildContext context) {
    final loadPercent = state.isCompleted
        ? 100
        : state.loadingProgress?.progressPercentage ?? 0;
    return AnimatedScale(
      duration: kThemeChangeDuration,
      curve: Curves.easeInOutCubic,
      scale: state.isCompleted ? 0 : 1,
      child: state.isFailed
          ? QuickBar.action(
              title: Text(context.t.loadImageFailed),
              actionTitle: Text(context.t.retry),
              onPressed: state.reLoadImage,
            )
          : QuickBar.progress(
              title: loadPercent > 1 ? Text('$loadPercent%') : null,
              progress:
                  state.isCompleted ? 1 : state.loadingProgress?.progressRatio,
            ),
    );
  }
}
