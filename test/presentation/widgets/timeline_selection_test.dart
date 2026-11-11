import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/version_repo.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/post_selection_provider.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cache;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';

class _MockVersionRepo extends Mock implements VersionRepo {}

class _MockImageCache extends Mock implements cache.DefaultCacheManager {}

/// The ring's stroke. Pinned here because it is what tells the ring apart from
/// the rating badge's hairline when both are on the same tile.
const double _ringWidth = 3.0;

Post _post(int id) => Post(
  id: id,
  serverId: 'test',
  originalFile: 'https://example.com/$id.jpg',
  sampleFile: 'https://example.com/$id.sample.jpg',
  previewFile: 'https://example.com/$id.preview.jpg',
  rateValue: 'g',
  score: 12,
  width: 100,
  height: 100,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final posts = [_post(1), _post(2)];

  setUp(() {
    // Thumbnails ask the disk cache, which has no path provider in a widget
    // test. An empty stream leaves every tile on its placeholder.
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
    CachedNetworkImageProvider.defaultCacheManager = imageCache;
  });

  final versionRepo = _MockVersionRepo();

  Widget harness({bool reducedMotion = false}) {
    when(() => versionRepo.current).thenReturn(AppVersion.zero);
    return ProviderScope(
      overrides: [
        // A null box keeps settings in memory: a real Hive write here outlives
        // the test and hangs teardown.
        settingsRepoProvider.overrideWithValue(UserSettingsRepo(null)),
        versionRepoProvider.overrideWithValue(versionRepo),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: Scaffold(
                body: CustomScrollView(slivers: [Timeline(posts: posts)]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The card's own box, measured through the transform so a scale shows up.
  Rect tile(WidgetTester tester, int index) =>
      tester.getRect(find.byType(Hero).at(index));

  /// The opacity actually painted over [subject], not the target the widget
  /// was handed: the target reaches its end on the first frame of the change.
  double opacityOver(WidgetTester tester, Finder subject) {
    return tester
        .renderObject<RenderAnimatedOpacity>(
          find
              .ancestor(of: subject, matching: find.byType(AnimatedOpacity))
              .first,
        )
        .opacity
        .value;
  }

  final ring = find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) return false;
    final decoration = widget.decoration;
    if (decoration is! BoxDecoration) return false;
    final border = decoration.border;
    return border is Border && border.top.width == _ringWidth;
  });

  Future<void> selectFirst(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Timeline)),
    );
    container.read(postSelectionProvider.notifier).toggle(posts.first.id);
    await tester.pump();
  }

  testWidgets('picking a tile settles it inside its own slot', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    final rest = tile(tester, 0);
    final neighbour = tile(tester, 1);

    await selectFirst(tester);
    await tester.pump(DesignTokens.durationFast);

    final picked = tile(tester, 0);
    expect(
      picked.width / rest.width,
      closeTo(DesignTokens.motionPickScale, 0.01),
    );
    expect(picked.center, rest.center);
    // Transform only: the grid never re-lays out around a selection, so the
    // tile beside it has not moved a pixel.
    expect(tile(tester, 1), neighbour);
  });

  testWidgets('the corner check hands over from the score, not over it', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(opacityOver(tester, find.byIcon(Icons.star_rounded)), 1.0);
    expect(opacityOver(tester, find.byIcon(Icons.check).first), 0.0);
    expect(opacityOver(tester, ring.first), 0.0);

    await selectFirst(tester);
    await tester.pump(DesignTokens.durationFast);

    expect(opacityOver(tester, find.byIcon(Icons.star_rounded).first), 0.0);
    expect(opacityOver(tester, find.byIcon(Icons.check).first), 1.0);
    expect(opacityOver(tester, ring.first), 1.0);
  });

  testWidgets('the ring is drawn on the tile edge, outside the clip', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    await selectFirst(tester);
    await tester.pump(DesignTokens.durationFast);

    // A border painted inside the rounded clip loses half its width to the
    // corner. The ring is a sibling of the clipped thumbnail instead, so it
    // covers the same box the tile covers.
    final ringRect = tester.getRect(ring.first);
    final tileRect = tile(tester, 0);
    expect(ringRect.width, closeTo(tileRect.width, 0.01));
    expect(ringRect.height, closeTo(tileRect.height, 0.01));
  });

  testWidgets('reduced motion drops the settle and keeps the fade', (
    tester,
  ) async {
    await tester.pumpWidget(harness(reducedMotion: true));
    await tester.pump();
    final rest = tile(tester, 0);

    await selectFirst(tester);
    // One frame: the scale is already at its target because its duration
    // collapsed, while the ring is still on its way in.
    expect(
      tile(tester, 0).width / rest.width,
      closeTo(DesignTokens.motionPickScale, 0.01),
    );

    await tester.pump(const Duration(milliseconds: 60));
    final fading = opacityOver(tester, ring.first);
    expect(fading, greaterThan(0.0));
    expect(fading, lessThan(1.0));

    await tester.pump(DesignTokens.durationFade);
    expect(opacityOver(tester, ring.first), 1.0);
  });
}
