import 'dart:async';
import 'dart:io';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';

class VideoPostSource {
  VideoPostSource({this.controller, this.hasError = false});

  final VideoPlayerController? controller;

  /// True once playback setup has failed: either the player could not be
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

  /// Bumped whenever a setup starts or is dropped. A continuation compares
  /// the value it captured before its last await, so a page change, a retry
  /// or a disposal invalidates the setups it interrupts: a slow lookup can
  /// no longer publish a controller over a newer one (leaking the player it
  /// replaced) or after the widget is gone.
  int _generation = 0;

  /// Flags the source as failed so the viewer shows its retry banner.
  void reportFailure() {
    if (!context.mounted) return;

    setState(() {
      source = source.copyWith(hasError: true);
    });
  }

  /// Streams the media straight from the server so playback can start before
  /// the whole file arrives, unless the video was watched before, in which
  /// case it replays from the disk cache without a request.
  ///
  /// Servers that hotlink-protect their CDN (Gelbooru among them) only accept
  /// the request with the same Referer/User-Agent headers the image requests
  /// already use. The background cache download sends the same ones, so the
  /// stored file is the response playback would have received.
  Future<void> createController() async {
    if (!hook.active) return;

    final generation = ++_generation;
    final mediaUrl = hook.post.content.url;
    final cache = hook.ref.read(videoCacheProvider);

    File? cached;
    try {
      // A cache lookup is a small index read, but playback must not wait on
      // storage or a platform channel that never answers: after this the
      // network path is taken and the video still plays.
      cached = await cache.lookup(mediaUrl).timeout(const Duration(seconds: 2));
    } catch (e, stack) {
      mainLog.w('VideoPost: failed to read the cache for $mediaUrl', e, stack);
    }
    if (!_stillCurrent(mediaUrl, generation)) return;

    if (cached != null) {
      final controller = VideoPlayerController.file(
        cached,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      unawaited(controller.setLooping(true));
      setState(() {
        source = source.copyWith(controller: controller);
      });
      return;
    }

    final Map<String, String> headers;
    try {
      final cookieJar = hook.ref.read(cookieJarProvider);
      final cookies = await cookieJar.loadForRequest(mediaUrl.toUri());
      if (!_stillCurrent(mediaUrl, generation)) return;
      headers = hook.ref.read(
        postHeadersFactoryProvider(hook.post, cookies: cookies),
      );
    } catch (e, stack) {
      // The request cannot be prepared even though the player is fine; an
      // unreadable cookie store, a header factory that throws. Fail the same
      // way as a broken player: an escaping error would leave the viewer on
      // a loader with no retry banner. A setup dropped while awaiting is not
      // a failure.
      if (!_stillCurrent(mediaUrl, generation)) return;
      mainLog.w(
        'VideoPost: failed to prepare the request for $mediaUrl',
        e,
        stack,
      );
      reportFailure();
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      mediaUrl.toUri(),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      httpHeaders: headers,
    );
    unawaited(controller.setLooping(true));

    setState(() {
      source = source.copyWith(controller: controller);
    });

    // Cache the same bytes while they stream, so the next visit can start
    // instantly. This never blocks playback; a failure only leaves this visit
    // streaming from the server.
    unawaited(cache.cache(mediaUrl, headers));
  }

  /// Whether this setup still owns the slot: [mediaUrl] still belongs to the
  /// post this hook shows, no newer setup or teardown has replaced it, and
  /// the widget is still able to take a controller.
  bool _stillCurrent(String mediaUrl, int generation) =>
      generation == _generation &&
      hook.active &&
      hook.post.content.url == mediaUrl &&
      context.mounted;

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
    _generation++;
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
