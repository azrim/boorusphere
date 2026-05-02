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
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Hoisted out of `build` so we don't allocate one [ImageFilter] per
/// repaint while the user is zooming or scrolling.
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
    final transformController = useTransformationController();
    final zoomAnimator =
        useAnimationController(duration: const Duration(milliseconds: 150));
    final wasZoomed = useRef(false);
    final tapPosition = useRef(Offset.zero);
    final retryNonce = useState(0);
    final loadState = useState<_PostImageLoadState>(
      const _PostImageLoadState.loading(0),
    );

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
          onZoomChanged?.call(zoomed);
        }
      }

      transformController.addListener(onTransformChange);
      return () => transformController.removeListener(onTransformChange);
    }, [transformController]);

    final imageUrl =
        contentSetting.loadOriginal ? post.originalFile : post.content.url;

    return GestureDetector(
      onTap: () {
        ref.read(fullscreenStateProvider.notifier).toggle();
      },
      onDoubleTapDown: (details) {
        tapPosition.value = details.localPosition;
      },
      onDoubleTap: () async {
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
      },
      child: RepaintBoundary(
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
                  key: ValueKey('$imageUrl-${retryNonce.value}'),
                  imageUrl: imageUrl,
                  httpHeaders: headers,
                  fit: BoxFit.contain,
                  imageBuilder: (context, provider) {
                    _scheduleLoadState(
                        loadState, const _PostImageLoadState.completed());
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
  const _PostImageStatus({
    required this.state,
    required this.onRetry,
  });

  final _PostImageLoadState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final completed = state is _PostImageCompleted;
    final loadPercent = switch (state) {
      _PostImageLoading(:final progress) => (progress * 100).round(),
      _PostImageCompleted() => 100,
      _PostImageFailed() => 0,
    };
    return AnimatedScale(
      duration: kThemeChangeDuration,
      curve: Curves.easeInOutCubic,
      scale: completed ? 0 : 1,
      child: state is _PostImageFailed
          ? QuickBar.action(
              title: Text(context.t.loadImageFailed),
              actionTitle: Text(context.t.retry),
              onPressed: onRetry,
            )
          : QuickBar.progress(
              title: loadPercent > 1 ? Text('$loadPercent%') : null,
              progress: completed ? 1 : (loadPercent / 100),
            ),
    );
  }
}
