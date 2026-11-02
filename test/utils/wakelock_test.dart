import 'package:boorusphere/utils/wakelock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the switch follows the last visible viewer', () {
    final calls = <bool>[];
    final manager = WakelockManager(
      setEnabled: (enabled) async => calls.add(enabled),
    );

    final below = Object();
    final above = Object();

    manager.acquire(below);
    manager.acquire(above);
    expect(calls, [true]);

    // A page above the viewer is pushed: the viewer below lets go first, and
    // the screen must stay awake for the one still visible.
    manager.release(below);
    expect(calls, [true]);

    manager.release(above);
    expect(calls, [true, false]);
  });

  test('a repeated release does not touch the switch again', () {
    final calls = <bool>[];
    final manager = WakelockManager(
      setEnabled: (enabled) async => calls.add(enabled),
    );

    final holder = Object();
    manager.release(holder);
    expect(calls, isEmpty);

    manager.acquire(holder);
    manager.acquire(holder);
    expect(calls, [true]);

    manager.release(holder);
    manager.release(holder);
    expect(calls, [true, false]);
  });
}
