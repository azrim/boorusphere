import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clock.g.dart';

/// The current time, behind a seam so the lock timers can be tested without
/// waiting through their real durations.
class Clock {
  const Clock();

  DateTime now() => DateTime.now();
}

@Riverpod(keepAlive: true)
Clock clock(Ref ref) {
  return const Clock();
}
