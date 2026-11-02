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

class MockCookieJar extends Mock implements CookieJar {}

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
}
