import 'dart:async';

import 'package:flutter/widgets.dart';
// The controller type is only re-exported by video_player; the platform
// interface it talks to is deliberately not part of that export.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Records the platform calls per player id, so a test can prove that a
/// controller the viewer dropped is actually torn down on the platform — not
/// just forgotten in Dart while its player keeps decoding and playing audio.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
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
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

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
