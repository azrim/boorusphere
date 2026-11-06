import 'package:boorusphere/data/repository/video_cache/video_cache.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'content_setting.freezed.dart';

/// Where the viewer's slideshow goes after the current post.
enum SlideshowDirection { forward, backward, random }

@freezed
abstract class ContentSetting with _$ContentSetting {
  const factory ContentSetting({
    @Default(true) bool blurExplicit,
    @Default(false) bool blurTimelineOnly,
    @Default(false) bool loadOriginal,
    @Default(false) bool videoMuted,
    @Default(SlideshowDirection.forward) SlideshowDirection slideshowDirection,
    @Default(6) int slideshowInterval,
    @Default(5) int videoSeekSeconds,
    @Default(false) bool volumeKeyNavigation,
    @Default(false) bool hideFavorited,
    @Default(false) bool hideDownloaded,
    @Default(VideoCache.defaultMaxBytes) int videoCacheMaxBytes,
  }) = _ContentSetting;
}
