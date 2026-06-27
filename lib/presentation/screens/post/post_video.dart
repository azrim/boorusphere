import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/screens/post/hooks/video_post.dart';
import 'package:boorusphere/presentation/screens/post/post_placeholder_image.dart';
import 'package:boorusphere/presentation/screens/post/post_toolbox.dart';
import 'package:boorusphere/presentation/screens/post/quickbar.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/utils/gestures/single_pointer_vertical_drag_recognizer.dart';
import 'package:boorusphere/presentation/utils/hooks/markmayneedrebuild.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

class PostVideo extends StatefulWidget {
  const PostVideo({
    super.key,
    required this.post,
    required this.onToolboxVisibilityChange,
    this.onShowDetails,
    this.onSwipeUp,
    this.onSwipeDown,
  });

  final Post post;
  final void Function(bool visible) onToolboxVisibilityChange;

  /// Wired by the post viewer to expand the details sheet. Used by both
  /// the new details icon button in the video toolbox and the swipe-up
  /// gesture (when [onSwipeUp] is null and [onShowDetails] is non-null).
  final VoidCallback? onShowDetails;

  /// Single-finger swipe-up (fast fling) handler. The post viewer wires
  /// this to expand the details sheet, mirroring the [PostImage] gesture
  /// stack.
  final VoidCallback? onSwipeUp;

  /// Single-finger swipe-down (fast fling) handler. The post viewer
  /// wires this to dismiss the route, mirroring the [PostImage] gesture
  /// stack.
  final VoidCallback? onSwipeDown;

  @override
  State<PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<PostVideo> {
  bool _visible = true;
  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey('video_${widget.post.id}_${widget.post.serverId}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        setState(() {
          _visible = info.visibleFraction > 0;
        });
      },
      child: _PostVideoContent(
        key: ValueKey(
          'video_content_${widget.post.id}_${widget.post.serverId}',
        ),
        post: widget.post,
        onToolboxVisibilityChange: widget.onToolboxVisibilityChange,
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
    required this.onToolboxVisibilityChange,
    required this.isVisible,
    this.onShowDetails,
    this.onSwipeUp,
    this.onSwipeDown,
  });

  final Post post;
  final bool isVisible;
  final void Function(bool visible) onToolboxVisibilityChange;
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
    final source = useVideoPostSource(ref, post: post, active: isActive);
    final controller = isBlur.value ? null : source.controller;

    onVisibilityChange(bool value) {
      showOverlay.value = value;
      showPauseOverlay.value = value;
      onToolboxVisibilityChange.call(value);
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
      controller?.initialize().whenComplete(() async {
        onFirstFrame() {
          controller.removeListener(onFirstFrame);
          markMayNeedRebuild();
        }

        controller.addListener(onFirstFrame);
        await controller.setVolume(contentSettings.videoMuted ? 0 : 1);
        if (isPlaying.value && context.mounted) {
          await controller.play();
          scheduleHide();
        }
      });
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
    return Column(
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
        _Progress(source: source),
      ],
    );
  }
}

/// Velocity-based swipe-up / swipe-down recognizer for the post viewer's
/// video player. Mirrors the [PostImage] gesture stack: rejects on
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
        icon: Icon(isPlaying ? Icons.pause_outlined : Icons.play_arrow),
        onPressed: onPressed,
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.source});

  final VideoPostSource source;

  double _getProgressValue(VideoPostSource src) {
    return src.progress.downloaded / (src.progress.totalSize ?? 1);
  }

  bool _isDownloading(VideoPostSource src) {
    final value = _getProgressValue(src);
    return value > 0 && value < 1;
  }

  @override
  Widget build(BuildContext context) {
    final controller = source.controller;

    if (controller == null || !controller.value.isInitialized) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
        child: Stack(
          children: [
            if (_isDownloading(source))
              LinearProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withAlpha(100),
                ),
                value: _getProgressValue(source),
                backgroundColor: Colors.transparent,
              ),
            LinearProgressIndicator(
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
              backgroundColor: Colors.white.withAlpha(20),
            ),
          ],
        ),
      );
    }

    return VideoProgressIndicator(
      controller,
      colors: VideoProgressColors(
        playedColor: Colors.red,
        backgroundColor: Colors.white.withAlpha(20),
      ),
      allowScrubbing: true,
      padding: const EdgeInsets.only(top: 16, bottom: 16),
    );
  }
}
