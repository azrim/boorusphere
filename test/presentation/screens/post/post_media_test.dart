import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/user_download_repo.dart';
import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/domain/repository/version_repo.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/cache.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/screens/post/post_media.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
// `DownloadProgress` is ambiguous here: the app's downloads entity shares the
// name with the cache manager's transfer progress, so hide the latter.
import 'package:cached_network_image/cached_network_image.dart'
    hide DownloadProgress;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    hide DownloadProgress;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../utils/fake_cache_manager.dart';
import '../../../utils/hive.dart';

class MockEnvRepo extends Mock implements EnvRepo {}

class MockVersionRepo extends Mock implements VersionRepo {}

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
  late MockCacheManager cache;
  late MockEnvRepo envRepo;
  late MockVersionRepo versionRepo;
  late StreamController<FileResponse> fileStream;

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

    cache = MockCacheManager();
    envRepo = MockEnvRepo();
    versionRepo = MockVersionRepo();
    fileStream = StreamController<FileResponse>.broadcast();

    when(() => envRepo.sdkVersion).thenReturn(33);
    when(() => envRepo.appVersion).thenReturn(AppVersion.zero);
    when(() => versionRepo.current).thenReturn(AppVersion.zero);
    when(
      () => cache.getFileStream(
        any(),
        headers: any(named: 'headers'),
        withProgress: any(named: 'withProgress'),
      ),
    ).thenAnswer((_) => fileStream.stream);
    when(() => cache.removeFile(any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    VisibilityDetectorController.instance.updateInterval = const Duration(
      milliseconds: 500,
    );
    await fileStream.close();
  });

  Widget harness(Post post) {
    return ProviderScope(
      overrides: [
        cacheManagerProvider.overrideWithValue(cache),
        envRepoProvider.overrideWithValue(envRepo),
        versionRepoProvider.overrideWithValue(versionRepo),
        fullscreenStateProvider.overrideWith(_FakeFullscreenState.new),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          // Without an active HeroMode the video surface never becomes
          // "active" and its download stream is never requested.
          home: HeroMode(
            enabled: true,
            child: Scaffold(body: PostMedia(post: post)),
          ),
        ),
      ),
    );
  }

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

  testWidgets('surfaces video failures and retries on demand', (tester) async {
    await tester.pumpWidget(harness(videoPost));
    // Let `createController`'s cookie lookup + stream subscription settle.
    await tester.pump();
    await tester.pump();

    // Healthy state: indeterminate progress bar, no error chrome.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(t.loadVideoFailed), findsNothing);

    // Simulate a download failure. No `FileInfo` is ever emitted, so no
    // `VideoPlayerController` (and thus no video plugin) is constructed.
    fileStream.addError(Exception('download failed'));
    await tester.pump();
    await tester.pump();

    expect(find.text(t.loadVideoFailed), findsOneWidget);
    expect(find.text(t.retry), findsOneWidget);
    // The progress bar is hidden while the error banner is up.
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text(t.retry));
    await tester.pump();
    await tester.pump();

    // Retry evicts the cached file and re-requests the stream.
    verify(() => cache.removeFile(videoPost.content.url)).called(1);
    verify(
      () => cache.getFileStream(
        videoPost.content.url,
        headers: any(named: 'headers'),
        withProgress: any(named: 'withProgress'),
      ),
    ).called(2);

    // The fresh stream carries no error, so the banner clears.
    expect(find.text(t.loadVideoFailed), findsNothing);

    // Drain the overlay auto-hide timer so no timers outlive the test.
    await tester.pump(const Duration(seconds: 2));
  });
}
