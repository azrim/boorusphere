import 'dart:async';
import 'dart:io';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/user_download_repo.dart';
import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/data/repository/video_cache/video_cache.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/domain/repository/version_repo.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_lock/app_lock_state.dart';
import 'package:boorusphere/presentation/provider/app_lock/entity/app_lock_data.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/content_setting.dart';
import 'package:boorusphere/presentation/routes/route_visibility.dart';
import 'package:boorusphere/presentation/screens/post/enhanced_post_viewer.dart';
import 'package:boorusphere/presentation/screens/post/post_media.dart';
// The cache manager exposes its own `DownloadProgress`; this test wants the
// downloads entity of the same name.
import 'package:cached_network_image/cached_network_image.dart'
    hide DownloadProgress;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cache;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../utils/hive.dart';
import '../../../utils/video_player.dart';

class _FakeAppLock extends AppLock {
  @override
  AppLockData build() => const AppLockData(enabled: true, hasPin: true);

  void setLocked(bool value) => state = state.copyWith(locked: value);
}

class _FakeContentSettings extends ContentSettingState {
  @override
  ContentSetting build() => const ContentSetting(volumeKeyNavigation: true);
}

class _FakeWakelock extends WakelockPlusPlatformInterface {
  final changes = <bool>[];

  @override
  Future<void> toggle({required bool enable}) async => changes.add(enable);
}

class _MockImageCache extends Mock implements cache.DefaultCacheManager {}

class MockEnvRepo extends Mock implements EnvRepo {}

class MockVersionRepo extends Mock implements VersionRepo {}

/// The viewer asks the disk cache before it builds a controller, and the path
/// provider plugin has no answer in widget tests. This stub keeps the surface
/// on the network path the retry banner covers.
class _StubVideoCache extends VideoCache {
  _StubVideoCache()
    : super(
        client: Dio(),
        directory: () async => throw UnsupportedError('no directory'),
      );

  @override
  Future<File?> lookup(String url) async => null;

  @override
  Future<File?> cache(String url, Map<String, String> headers) async => null;
}

/// The real [FullscreenState] reads `envRepoProvider` from its own dispose
/// hook, which throws once the test's container is torn down. The video
/// surface only needs the boolean, so skip the hook here.
class _FakeFullscreenState extends FullscreenState {
  @override
  bool build() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveTestContainer hiveContainer;
  late MockEnvRepo envRepo;
  late MockVersionRepo versionRepo;

  Post makePost({
    required int id,
    required String original,
    required String sample,
    String? preview,
  }) {
    return Post(
      id: id,
      serverId: 'test',
      originalFile: original,
      sampleFile: sample,
      previewFile: preview ?? sample,
      // `g` resolves to questionable — never explicit, so nothing blurs.
      rateValue: 'g',
      width: 100,
      height: 100,
    );
  }

  final imagePost = makePost(
    id: 1,
    original: 'https://example.com/original.jpg',
    sample: 'https://example.com/sample.jpg',
    preview: 'https://example.com/preview.jpg',
  );
  final unknownPost = makePost(
    id: 2,
    original: 'https://example.com/original.zip',
    sample: 'https://example.com/sample.zip',
    preview: 'https://example.com/preview.zip',
  );
  final videoPost = makePost(
    id: 3,
    original: 'https://example.com/original.mp4',
    sample: 'https://example.com/sample.jpg',
    preview: 'https://example.com/preview.jpg',
  );

  setUpAll(() async {
    hiveContainer = HiveTestContainer();
    // Toolbox (favorite + download buttons) reads these three boxes; the
    // downloads boxes are opened directly to skip `UserDownloadsRepo.prepare`
    // (which would call `FlutterDownloader.initialize`).
    await UserSettingsRepo.prepare();
    await UserFavoritePostRepo.prepare();
    await Hive.openBox<DownloadEntry>(UserDownloadsRepo.entryKey);
    await Hive.openBox<DownloadProgress>(UserDownloadsRepo.progressKey);
  });

  tearDownAll(() async {
    await hiveContainer.dispose();
  });

  setUp(() {
    // The default 500 ms update interval arms a repeating Timer that would
    // outlive the test; deferring to a post-frame callback instead keeps the
    // fake clock clean.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;

    final imageCache = _MockImageCache();
    when(
      () => imageCache.getImageFile(
        any(),
        key: any(named: 'key'),
        headers: any(named: 'headers'),
        withProgress: any(named: 'withProgress'),
        maxHeight: any(named: 'maxHeight'),
        maxWidth: any(named: 'maxWidth'),
      ),
    ).thenAnswer((_) => const Stream.empty());
    // Assign without reading the lazy default: constructing it starts disk
    // and path-provider work. Each test in this isolate installs a fresh fake.
    CachedNetworkImageProvider.defaultCacheManager = imageCache;

    envRepo = MockEnvRepo();
    versionRepo = MockVersionRepo();

    when(() => envRepo.sdkVersion).thenReturn(33);
    when(() => envRepo.appVersion).thenReturn(AppVersion.zero);
    when(() => versionRepo.current).thenReturn(AppVersion.zero);
  });

  tearDown(() {
    VisibilityDetectorController.instance.updateInterval = const Duration(
      milliseconds: 500,
    );
  });

  Widget harness(
    Post post, {
    ValueChanged<bool>? onZoomChanged,
    Listenable? zoomResetSignal,
    bool viewer = false,
    bool reducedMotion = false,
    List<NavigatorObserver> navigatorObservers = const [],
  }) {
    final body = viewer
        ? EnhancedPostViewer(initial: 0, posts: [post, unknownPost])
        : PostMedia(
            post: post,
            onZoomChanged: onZoomChanged,
            zoomResetSignal: zoomResetSignal,
          );
    return ProviderScope(
      overrides: [
        appLockProvider.overrideWith(_FakeAppLock.new),
        settingsRepoProvider.overrideWithValue(UserSettingsRepo(null)),
        contentSettingStateProvider.overrideWith(_FakeContentSettings.new),
        envRepoProvider.overrideWithValue(envRepo),
        versionRepoProvider.overrideWithValue(versionRepo),
        fullscreenStateProvider.overrideWith(_FakeFullscreenState.new),
        videoCacheProvider.overrideWithValue(_StubVideoCache()),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          navigatorObservers: navigatorObservers,
          // Without an active HeroMode the video surface never becomes
          // "active" and its download stream is never requested.
          home: HeroMode(
            enabled: true,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reducedMotion),
                child: Scaffold(body: body),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('locking releases the video player without a route change', (
    tester,
  ) async {
    final platform = FakeVideoPlayerPlatform();
    final previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previous);

    await tester.pumpWidget(harness(videoPost));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(platform.played, isNotEmpty);
    final player = platform.created.single;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PostMedia)),
    );
    final lock = container.read(appLockProvider.notifier) as _FakeAppLock;
    lock.setLocked(true);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(platform.paused, contains(player));
    expect(platform.disposed, contains(player));
    final creations = platform.created.length;
    await tester.pump(const Duration(seconds: 3));
    expect(platform.created, hasLength(creations));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lock cover releases viewer keys and stops the slideshow', (
    tester,
  ) async {
    const channel = MethodChannel('io.chaldeaprjkt.boorusphere/volume_keys');
    const codec = StandardMethodCodec();
    final messenger = tester.binding.defaultBinaryMessenger;
    final capture = <bool>[];
    final wakelock = _FakeWakelock();
    final previousWakelock = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = wakelock;
    addTearDown(() {
      WakelockPlusPlatformInterface.instance = previousWakelock;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      capture.add(call.arguments['enabled'] as bool);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(harness(imagePost, viewer: true));
    await tester.pump();
    expect(capture.last, isTrue);
    final page = tester.widget<PageView>(find.byType(PageView)).controller!;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EnhancedPostViewer)),
    );
    final lock = container.read(appLockProvider.notifier) as _FakeAppLock;
    // The chrome arrives once the surface has landed, so the controls are not
    // on screen until the handover has run.
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.viewer.startSlideshow));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    lock.setLocked(true);
    // Dispatch before the viewer rebuilds: the old handler must refuse too.
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('onVolumeKey', 'up')),
      (_) {},
    );
    await tester.pump();
    expect(capture.last, isFalse);
    expect(wakelock.changes, [true, false]);
    await tester.pump(const Duration(seconds: 10));
    expect(page.page, 0);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    lock.setLocked(false);
    await tester.pump();
    expect(capture.last, isTrue);
    expect(wakelock.changes, [true, false, true]);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(capture.last, isFalse);
  });

  testWidgets('dispatches photo posts to the image renderer', (tester) async {
    await tester.pumpWidget(harness(imagePost));

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsWidgets);
    // The first frame is still the loading state; the retry chrome only
    // shows once the (failing) network image resolves.
    expect(find.text(t.retry), findsNothing);
  });

  testWidgets('dispatches unsupported posts to the external opener', (
    tester,
  ) async {
    await tester.pumpWidget(harness(unknownPost));

    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text(t.unsupportedMedia(fileExt: 'zip')), findsOneWidget);
    expect(find.text(t.openExternally), findsOneWidget);
  });

  testWidgets('a zoom reset at rest releases the viewer claim', (tester) async {
    final reset = ValueNotifier<int>(0);
    final zoomChanges = <bool>[];
    addTearDown(reset.dispose);

    await tester.pumpWidget(
      harness(
        imagePost,
        zoomResetSignal: reset,
        onZoomChanged: zoomChanges.add,
      ),
    );

    reset.value++;
    await tester.pump();

    // The image never left fit-to-screen, so nothing else reports it. Without
    // this the viewer would believe it is still zoomed and swallow Back.
    expect(zoomChanges, [false]);
  });

  testWidgets('surfaces the retry banner when playback cannot start', (
    tester,
  ) async {
    await tester.pumpWidget(harness(videoPost));
    // Let `createController`'s cookie lookup settle.
    await tester.pump();
    await tester.pump();

    // The video plugin is unavailable in widget tests, so initialization
    // fails and the viewer has to offer a manual retry.
    expect(find.text(t.loadVideoFailed), findsOneWidget);
    expect(find.text(t.retry), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Drain the overlay auto-hide timer so no timers outlive the test.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'reduced motion opens the viewer and steps the slideshow by jump',
    (tester) async {
      await tester.pumpWidget(
        harness(imagePost, viewer: true, reducedMotion: true),
      );
      await tester.pump();
      // The details sheet is built with the viewer: a zero snap duration
      // asserts in the DraggableScrollableSheet constructor before anything
      // else runs.
      expect(tester.takeException(), isNull);

      final page = tester.widget<PageView>(find.byType(PageView)).controller!;
      await tester.tap(find.byTooltip(t.viewer.startSlideshow));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // The default interval is 6 s. The step must jump: a zero-duration
      // animateToPage asserts in the scroll activity it would create.
      await tester.pump(const Duration(seconds: 7));
      expect(page.page, 1);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip(t.viewer.stopSlideshow));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Back mid-double-tap turns the zoom around', (tester) async {
    // The viewer's PageView gives the image tight bounds; the standalone
    // surface collapses to the (never-loading) placeholder's zero size.
    await tester.pumpWidget(harness(imagePost, viewer: true));
    await tester.pump();

    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pump();
    // Mid-flight in the 150 ms double-tap zoom.
    await tester.pump(const Duration(milliseconds: 60));

    final transform = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1.01));

    // Back while the zoom is still travelling: the viewer resets the zoom
    // instead of popping, retargeting the same animation from where the
    // image is rather than stacking a second one.
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(navigator.maybePop());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(transform.value.getMaxScaleOnAxis(), 1.0);
    expect(find.byType(EnhancedPostViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a covering route stops the slideshow for good', (tester) async {
    await tester.pumpWidget(
      harness(imagePost, viewer: true, navigatorObservers: [appRouteObserver]),
    );
    await tester.pump();
    final page = tester.widget<PageView>(find.byType(PageView)).controller!;
    // The chrome arrives once the surface has landed.
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.viewer.startSlideshow));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // A non-opaque route does not mute the viewer's tickers; the route
    // observer is what tells it to let go.
    final navigator = Navigator.of(
      tester.element(find.byType(EnhancedPostViewer)),
    );
    unawaited(
      navigator.push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(page.page, 0);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Uncovering does not resume on its own: playing again is a tap.
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(page.page, 0);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
