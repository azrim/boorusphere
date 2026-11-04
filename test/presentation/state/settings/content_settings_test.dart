import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/video_cache/video_cache.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/content_setting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/hive.dart';
import '../../../utils/riverpod.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContentSetting', () {
    final ref = ProviderContainer();
    final hiveContainer = HiveTestContainer();

    notifier() => ref.read(contentSettingStateProvider.notifier);
    state() => ref.read(contentSettingStateProvider);

    setUpAll(() async {
      await UserSettingsRepo.prepare();
      ref.setupTestFor(contentSettingStateProvider);
    });

    tearDownAll(() async {
      await hiveContainer.dispose();
      ref.dispose();
    });

    test('blurExplicit', () async {
      await notifier().setBlurExplicitPost(false);

      expect(state().blurExplicit, false);
    });

    test('blurTimelineOnly', () async {
      await notifier().setBlurTimelineOnly(true);

      expect(state().blurTimelineOnly, true);
    });

    test('loadOriginal', () async {
      await notifier().setLoadOriginalPost(true);

      expect(state().loadOriginal, true);
    });

    test('videoMuted', () async {
      final initial = state().videoMuted;
      await notifier().toggleVideoPlayerMute();

      expect(state().videoMuted, !initial);
    });

    test('slideshow direction survives a name round-trip', () async {
      await notifier().setSlideshowDirection(SlideshowDirection.backward);
      expect(state().slideshowDirection, SlideshowDirection.backward);
    });

    test('slideshow interval is clamped to 3..15', () async {
      await notifier().setSlideshowInterval(1);
      expect(state().slideshowInterval, 3);

      await notifier().setSlideshowInterval(99);
      expect(state().slideshowInterval, 15);

      await notifier().setSlideshowInterval(8);
      expect(state().slideshowInterval, 8);
    });

    test('video seek step is clamped to 2..15', () async {
      await notifier().setVideoSeekSeconds(0);
      expect(state().videoSeekSeconds, 2);

      await notifier().setVideoSeekSeconds(20);
      expect(state().videoSeekSeconds, 15);
    });

    test('volume key navigation can be turned off', () async {
      await notifier().setVolumeKeyNavigation(false);
      expect(state().volumeKeyNavigation, false);

      await notifier().setVolumeKeyNavigation(true);
      expect(state().volumeKeyNavigation, true);
    });

    test('local feed filters start off and can be turned on', () async {
      expect(state().hideFavorited, false);
      expect(state().hideDownloaded, false);

      await notifier().setHideFavorited(true);
      expect(state().hideFavorited, true);

      await notifier().setHideDownloaded(true);
      expect(state().hideDownloaded, true);
    });

    test('video cache limit is clamped to the offered range', () async {
      await notifier().setVideoCacheMaxBytes(1);
      expect(state().videoCacheMaxBytes, VideoCache.minBudgetBytes);

      await notifier().setVideoCacheMaxBytes(9 * 1024 * 1024 * 1024);
      expect(state().videoCacheMaxBytes, VideoCache.maxBudgetBytes);

      await notifier().setVideoCacheMaxBytes(500 * 1024 * 1024);
      expect(state().videoCacheMaxBytes, 500 * 1024 * 1024);
    });
  });
}
