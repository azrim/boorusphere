import 'dart:async';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/cache.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';

class VideoPostSource {
  VideoPostSource({
    this.progress = const DownloadProgress('', 0, 0),
    this.controller,
    this.hasError = false,
  });

  final DownloadProgress progress;
  final VideoPlayerController? controller;

  /// True once playback setup has failed — either the download stream
  /// errored or the player failed to initialize. The viewer surfaces a
  /// manual retry banner while set. Cleared when [destroyController]
  /// resets the source.
  final bool hasError;

  VideoPostSource copyWith({
    DownloadProgress? progress,
    VideoPlayerController? controller,
    bool? hasError,
  }) {
    return VideoPostSource(
      progress: progress ?? this.progress,
      controller: controller ?? this.controller,
      hasError: hasError ?? this.hasError,
    );
  }

  @override
  bool operator ==(covariant VideoPostSource other) {
    if (identical(this, other)) return true;

    return other.progress == progress &&
        other.controller == controller &&
        other.hasError == hasError;
  }

  @override
  int get hashCode => Object.hash(progress, controller, hasError);
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
  _VideoPostState();

  VideoPostSource source = VideoPostSource();
  StreamSubscription? _cacheSubscription;

  void onFileStream(FileResponse event) {
    if (!context.mounted) return;

    if (event is DownloadProgress) {
      setState(() {
        source = source.copyWith(progress: event);
      });
    } else if (event is FileInfo) {
      final controller = VideoPlayerController.file(
        event.file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      )..setLooping(true);
      final size = event.file.statSync().size;
      final prog = DownloadProgress(event.originalUrl, size, size);

      setState(() {
        source = source.copyWith(controller: controller, progress: prog);
      });
    }
  }

  /// Flags the source as failed so the viewer shows its retry banner.
  /// Fired both when the download stream errors and when
  /// [VideoPlayerController.initialize] throws.
  void reportFailure() {
    if (!context.mounted) return;

    setState(() {
      source = source.copyWith(hasError: true);
    });
  }

  Future<void> createController() async {
    if (!hook.active) return;

    final cache = hook.ref.read(cacheManagerProvider);
    final cookieJar = hook.ref.read(cookieJarProvider);
    final cookies = await cookieJar.loadForRequest(
      hook.post.content.url.toUri(),
    );
    final headers = hook.ref.read(
      postHeadersFactoryProvider(hook.post, cookies: cookies),
    );

    _cacheSubscription = cache
        .getFileStream(
          hook.post.content.url,
          headers: headers,
          withProgress: true,
        )
        .listen(onFileStream, onError: (Object _) => reportFailure());
  }

  /// Manual retry: drop the failed controller, evict the cached file and
  /// re-request the stream. The fresh controller instance re-triggers the
  /// viewer's `useEffect([controller])`, so no extra nonce is required.
  Future<void> retry() async {
    final cache = hook.ref.read(cacheManagerProvider);
    destroyController();
    // Force a rebuild so the disposed controller is dropped from the tree
    // before the replacement stream produces a new one.
    setState(() {});
    await cache.removeFile(hook.post.content.url);
    await createController();
  }

  void destroyController() {
    _cacheSubscription?.cancel();
    _cacheSubscription = null;
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
