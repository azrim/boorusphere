import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/video_cache/video_cache.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/settings/entity/content_setting.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'content_setting_state.g.dart';

@riverpod
class ContentSettingState extends _$ContentSettingState {
  /// Slideshow pace bounds. Stored values are clamped on read as well, so a
  /// hand-edited or older archive cannot leave the timer at zero or at a
  /// minutes-long interval.
  static const minSlideshowInterval = 3;
  static const maxSlideshowInterval = 15;
  static const minVideoSeekSeconds = 2;
  static const maxVideoSeekSeconds = 15;

  /// Video cache budgets the settings offer, in megabytes. A stored value is
  /// clamped to the range [VideoCache] publishes, so an imported archive cannot
  /// leave the cache with no room or let it grow past a gigabyte.
  static const videoCacheLimitMegabytes = [100, 300, 500, 1024];

  @override
  ContentSetting build() {
    final repo = ref.read(settingsRepoProvider);
    return ContentSetting(
      blurExplicit: repo.get(Setting.postBlurExplicit, or: true),
      blurTimelineOnly: repo.get(Setting.postBlurTimelineOnly, or: false),
      loadOriginal: repo.get(Setting.postLoadOriginal, or: false),
      videoMuted: repo.get(Setting.videoPlayerMuted, or: false),
      slideshowDirection: _directionFrom(
        repo.get(
          Setting.viewerSlideshowDirection,
          or: SlideshowDirection.forward.name,
        ),
      ),
      slideshowInterval: repo
          .get(Setting.viewerSlideshowInterval, or: 6)
          .clamp(minSlideshowInterval, maxSlideshowInterval)
          .toInt(),
      videoSeekSeconds: repo
          .get(Setting.viewerVideoSeekSeconds, or: 5)
          .clamp(minVideoSeekSeconds, maxVideoSeekSeconds)
          .toInt(),
      volumeKeyNavigation: repo.get(
        Setting.viewerVolumeKeyNavigation,
        or: false,
      ),
      hideFavorited: repo.get(Setting.timelineHideFavorited, or: false),
      hideDownloaded: repo.get(Setting.timelineHideDownloaded, or: false),
      videoCacheMaxBytes: VideoCache.budgetFrom(
        repo.get(Setting.videoCacheMaxBytes, or: VideoCache.defaultMaxBytes),
      ),
    );
  }

  SlideshowDirection _directionFrom(String name) {
    return SlideshowDirection.values.firstWhere(
      (it) => it.name == name,
      orElse: () => SlideshowDirection.forward,
    );
  }

  Future<void> setBlurExplicitPost(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(blurExplicit: value);
    await repo.put(Setting.postBlurExplicit, value);
  }

  Future<void> setBlurTimelineOnly(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(blurTimelineOnly: value);
    await repo.put(Setting.postBlurTimelineOnly, value);
  }

  Future<void> setLoadOriginalPost(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(loadOriginal: value);
    await repo.put(Setting.postLoadOriginal, value);
  }

  Future<bool> toggleVideoPlayerMute() async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(videoMuted: !state.videoMuted);
    await repo.put(Setting.videoPlayerMuted, state.videoMuted);
    return state.videoMuted;
  }

  Future<void> setSlideshowDirection(SlideshowDirection direction) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(slideshowDirection: direction);
    await repo.put(Setting.viewerSlideshowDirection, direction.name);
  }

  Future<void> setSlideshowInterval(int seconds) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(
      slideshowInterval: seconds
          .clamp(minSlideshowInterval, maxSlideshowInterval)
          .toInt(),
    );
    await repo.put(Setting.viewerSlideshowInterval, state.slideshowInterval);
  }

  Future<void> setVideoSeekSeconds(int seconds) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(
      videoSeekSeconds: seconds
          .clamp(minVideoSeekSeconds, maxVideoSeekSeconds)
          .toInt(),
    );
    await repo.put(Setting.viewerVideoSeekSeconds, state.videoSeekSeconds);
  }

  Future<void> setVolumeKeyNavigation(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(volumeKeyNavigation: value);
    await repo.put(Setting.viewerVolumeKeyNavigation, value);
  }

  Future<void> setHideFavorited(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(hideFavorited: value);
    await repo.put(Setting.timelineHideFavorited, value);
  }

  Future<void> setHideDownloaded(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(hideDownloaded: value);
    await repo.put(Setting.timelineHideDownloaded, value);
  }

  Future<void> setVideoCacheMaxBytes(int bytes) async {
    final repo = ref.read(settingsRepoProvider);
    final budget = VideoCache.budgetFrom(bytes);
    state = state.copyWith(videoCacheMaxBytes: budget);
    await repo.put(Setting.videoCacheMaxBytes, budget);
  }
}
