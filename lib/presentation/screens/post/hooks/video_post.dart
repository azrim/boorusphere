import 'dart:async';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';

class VideoPostSource {
  VideoPostSource({this.controller, this.hasError = false});

  final VideoPlayerController? controller;

  /// True once playback setup has failed — either the player could not be
  /// created or [VideoPlayerController.initialize] threw. The viewer surfaces
  /// a manual retry banner while set. Cleared when [destroyController]
  /// resets the source.
  final bool hasError;

  VideoPostSource copyWith({
    VideoPlayerController? controller,
    bool? hasError,
  }) {
    return VideoPostSource(
      controller: controller ?? this.controller,
      hasError: hasError ?? this.hasError,
    );
  }

  @override
  bool operator ==(covariant VideoPostSource other) {
    if (identical(this, other)) return true;

    return other.controller == controller && other.hasError == hasError;
  }

  @override
  int get hashCode => Object.hash(controller, hasError);
}

/// Handle returned by [useVideoPostSource]: the current [VideoPostSource]
/// plus the two failure-path callbacks the viewer wires into its chrome.
typedef VideoPostHandle = ({
  VideoPostSource source,
  void Function() reportFailure,
  Future<void> Function() retry,
});

VideoPostHandle useVideoPostSource(
  WidgetRef ref, {
  required Post post,
  required bool active,
}) {
  return use(_VideoPostHook(ref, post: post, active: active));
}

class _VideoPostHook extends Hook<VideoPostHandle> {
  const _VideoPostHook(this.ref, {required this.post, required this.active});

  final WidgetRef ref;
  final Post post;
  final bool active;

  @override
  _VideoPostState createState() => _VideoPostState();
}

class _VideoPostState extends HookState<VideoPostHandle, _VideoPostHook> {
  VideoPostSource source = VideoPostSource();

  /// Flags the source as failed so the viewer shows its retry banner.
  void reportFailure() {
    if (!context.mounted) return;

    setState(() {
      source = source.copyWith(hasError: true);
    });
  }

  /// Streams the media straight from the server so playback can start before
  /// the whole file arrives. Servers that hotlink-protect their CDN (Gelbooru
  /// among them) only accept the request with the same Referer/User-Agent
  /// headers the image requests already use.
  Future<void> createController() async {
    if (!hook.active) return;

    final cookieJar = hook.ref.read(cookieJarProvider);
    final cookies = await cookieJar.loadForRequest(
      hook.post.content.url.toUri(),
    );
    final headers = hook.ref.read(
      postHeadersFactoryProvider(hook.post, cookies: cookies),
    );

    final controller = VideoPlayerController.networkUrl(
      hook.post.content.url.toUri(),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      httpHeaders: headers,
    );
    unawaited(controller.setLooping(true));

    if (!context.mounted) {
      unawaited(controller.dispose());
      return;
    }

    setState(() {
      source = source.copyWith(controller: controller);
    });
  }

  /// Manual retry: drop the failed controller and request the media again. The
  /// fresh controller instance re-triggers the viewer's
  /// `useEffect([controller])`, so no extra nonce is required.
  Future<void> retry() async {
    destroyController();
    // Force a rebuild so the disposed controller is dropped from the tree
    // before the replacement is created.
    setState(() {});
    await createController();
  }

  void destroyController() {
    unawaited(source.controller?.pause());
    source.controller?.dispose();
    source = VideoPostSource();
  }

  @override
  void initHook() {
    super.initHook();
    createController();
  }

  @override
  void didUpdateHook(_VideoPostHook oldHook) {
    super.didUpdateHook(oldHook);
    if (oldHook.active != hook.active || oldHook.post.id != hook.post.id) {
      destroyController();
      createController();
    }
  }

  @override
  VideoPostHandle build(BuildContext context) =>
      (source: source, reportFailure: reportFailure, retry: retry);

  @override
  void dispose() {
    destroyController();
    super.dispose();
  }

  @override
  String get debugLabel => 'useVideoPost';
}
