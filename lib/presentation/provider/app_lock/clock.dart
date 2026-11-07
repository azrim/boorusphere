import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clock.g.dart';

/// The current time, behind a seam so the lock timers can be tested without
/// waiting through their real durations.
class Clock {
  Clock();

  final Stopwatch _monotonic = Stopwatch()..start();

  DateTime now() => DateTime.now();

  /// Time since this clock was created, untouched by changes to the system
  /// clock. A live throttle is measured here; the wall clock is only the
  /// record's fallback across a restart, where this count starts over.
  Duration elapsed() => _monotonic.elapsed;
}

@Riverpod(keepAlive: true)
Clock clock(Ref ref) {
  return Clock();
}
