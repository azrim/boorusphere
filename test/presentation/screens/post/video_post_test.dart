import 'dart:async';
import 'dart:io';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/video_cache/video_cache.dart';
import 'package:boorusphere/presentation/screens/post/hooks/video_post.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';
// The controller type is only re-exported by video_player; the platform
// interface it talks to is deliberately not part of that export.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class MockCookieJar extends Mock implements CookieJar {}

/// Records the platform calls per player id, so a test can prove that a
/// controller the hook dropped is actually torn down on the platform — not
/// just forgotten in Dart while its player keeps decoding and playing audio.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final created = <int>[];
  final disposed = <int>[];
  final played = <int>[];
  final paused = <int>[];

  int _nextId = 1;
  final _events = <int, StreamController<VideoEvent>>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    created.add(id);
    // Single-subscription, so the initialized event is buffered until
    // `initialize` subscribes a moment later.
    final events = StreamController<VideoEvent>()
      ..add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 1),
          size: const Size(100, 100),
        ),
      );
    _events[id] = events;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async => played.add(playerId);

  @override
  Future<void> pause(int playerId) async => paused.add(playerId);

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}
}

/// A cache whose lookups stay pending until the test releases them, so two
/// setups can be in flight at once.
class _GatedVideoCache extends VideoCache {
  _GatedVideoCache()
    : super(
        client: Dio(),
        directory: () async => throw UnsupportedError('no directory'),
      );

  final lookups = <String, List<Completer<File?>>>{};

  Completer<File?> lookupCall(String url, int index) => lookups[url]![index];

  @override
  Future<File?> lookup(String url) {
    final completer = Completer<File?>();
    lookups.putIfAbsent(url, () => []).add(completer);
    return completer.future;
  }

  @override
  Future<File?> cache(String url, Map<String, String> headers) async => null;
}

class _Probe extends HookConsumerWidget {
  const _Probe({required this.post, required this.seen});

  final Post post;
  final List<VideoPostSource> seen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handle = useVideoPostSource(ref, post: post, active: true);
    seen.add(handle.source);
    return const SizedBox.shrink();
  }
}

void main() {
  const urlA = 'https://example.com/a.mp4';
  const urlB = 'https://example.com/b.mp4';

  Post post(int id, String url) => Post(
    id: id,
    serverId: 'test',
    originalFile: url,
    sampleFile: 'https://example.com/sample.jpg',
    previewFile: 'https://example.com/sample.jpg',
    rateValue: 'g',
    width: 100,
    height: 100,
  );

  Widget harness({
    required VideoCache cache,
    required Post post,
    required List<VideoPostSource> seen,
    CookieJar? cookieJar,
  }) {
    return ProviderScope(
      overrides: [
        videoCacheProvider.overrideWithValue(cache),
        if (cookieJar != null) cookieJarProvider.overrideWithValue(cookieJar),
      ],
      child: _Probe(post: post, seen: seen),
    );
  }

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com/'));
  });

  // The first pump only delivers the awaited lookup; the rebuild that its
  // continuation schedules is drawn by the next one.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  // `VideoPlayerController.dispose` awaits work chained behind the platform
  // subscription, which needs a real event-loop turn: pumping only gets as
  // far as cancelling the event subscription. Run outside the fake-async
  // zone so the platform player is actually released before we assert.
  Future<void> drainRealAsync(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }

  testWidgets('a superseded lookup cannot publish a controller', (
    tester,
  ) async {
    final cache = _GatedVideoCache();
    final seen = <VideoPostSource>[];

    await tester.pumpWidget(
      harness(cache: cache, post: post(1, urlA), seen: seen),
    );
    await tester.pumpWidget(
      harness(cache: cache, post: post(2, urlB), seen: seen),
    );
    await tester.pumpWidget(
      harness(cache: cache, post: post(1, urlA), seen: seen),
    );

    expect(cache.lookups[urlA], hasLength(2));
    expect(cache.lookups[urlB], hasLength(1));

    // The first setup for A resumes after the viewer left that page and came
    // back. Its URL matches again, so only the generation can tell it apart;
    // publishing here would leak the player it replaced.
    cache.lookupCall(urlA, 0).complete(File('stale-a.mp4'));
    await settle(tester);
    expect(seen.last.controller, isNull);
    expect(seen.last.hasError, false);

    // B was superseded as well.
    cache.lookupCall(urlB, 0).complete(File('stale-b.mp4'));
    await settle(tester);
    expect(seen.last.controller, isNull);

    // The setup that still owns the slot is the only one allowed to publish.
    cache.lookupCall(urlA, 1).complete(File('current-a.mp4'));
    await settle(tester);
    expect(seen.last.controller, isNotNull);
    expect(seen.last.hasError, false);
  });

  testWidgets('a failed request setup reports instead of escaping', (
    tester,
  ) async {
    final cache = _GatedVideoCache();
    final jar = MockCookieJar();
    final seen = <VideoPostSource>[];

    when(
      () => jar.loadForRequest(any()),
    ).thenThrow(StateError('cookie store unavailable'));

    await tester.pumpWidget(
      harness(cache: cache, post: post(1, urlA), seen: seen, cookieJar: jar),
    );

    // No cached copy, so the hook moves on to preparing the network request.
    cache.lookupCall(urlA, 0).complete(null);
    await settle(tester);

    // An escaping error would leave the viewer on a loader with no retry.
    expect(seen.last.controller, isNull);
    expect(seen.last.hasError, true);
  });

  testWidgets('a superseded controller is torn down on the platform', (
    tester,
  ) async {
    final cache = _GatedVideoCache();
    final seen = <VideoPostSource>[];
    final platform = _FakeVideoPlayerPlatform();
    final previousPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = platform;

    try {
      await tester.pumpWidget(
        harness(cache: cache, post: post(1, urlA), seen: seen),
      );
      cache.lookupCall(urlA, 0).complete(File('a.mp4'));
      await settle(tester);

      final first = seen.last.controller!;
      await first.initialize();
      await first.play();
      expect(platform.created, hasLength(1));
      final playerId = platform.created.single;
      expect(platform.played, contains(playerId));

      // Advance to the next post while its own lookup is still pending, so
      // the page the user left is the only setup being torn down here.
      await tester.pumpWidget(
        harness(cache: cache, post: post(2, urlB), seen: seen),
      );
      expect(seen.last.controller, isNull);

      // Silence is the point: the platform player behind the replaced
      // controller must stop immediately, or it keeps playing audio after
      // its page is gone.
      expect(platform.paused, contains(playerId));

      // And the player itself is released, not merely muted.
      await drainRealAsync(tester);
      expect(platform.disposed, contains(playerId));

      // The next page still publishes normally once its lookup lands.
      cache.lookupCall(urlB, 0).complete(File('b.mp4'));
      await settle(tester);
      expect(seen.last.controller, isNotNull);
      expect(seen.last.controller, isNot(same(first)));
    } finally {
      // Unmount while the fake is still installed: disposing a controller
      // reaches the platform, and the real one must not be initialized from
      // here.
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await drainRealAsync(tester);
      VideoPlayerPlatform.instance = previousPlatform;
    }
  });

  testWidgets('a setup resuming after the viewer closes publishes nothing', (
    tester,
  ) async {
    final cache = _GatedVideoCache();
    final seen = <VideoPostSource>[];

    await tester.pumpWidget(
      harness(cache: cache, post: post(1, urlA), seen: seen),
    );

    // The viewer closes while the cache lookup is still in flight.
    await tester.pumpWidget(const SizedBox());

    cache.lookupCall(urlA, 0).complete(File('late.mp4'));
    await settle(tester);

    // Publishing here would touch a disposed hook; the lookup is dropped.
    expect(seen.last.controller, isNull);
    expect(seen.last.hasError, false);
  });
}
