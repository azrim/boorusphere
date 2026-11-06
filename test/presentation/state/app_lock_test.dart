import 'dart:async';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/domain/repository/app_lock_repo.dart';
import 'package:boorusphere/presentation/provider/app_lock/app_lock_state.dart';
import 'package:boorusphere/presentation/provider/app_lock/biometric_auth.dart';
import 'package:boorusphere/presentation/provider/app_lock/clock.dart';
import 'package:boorusphere/presentation/provider/app_lock/entity/app_lock_data.dart';
import 'package:boorusphere/presentation/provider/app_lock/lockout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../utils/riverpod.dart';

class _FakeAppLockRepo implements AppLockRepo {
  _FakeAppLockRepo({
    this.enabled = true,
    this.pin = '1234',
    this.timeout = LockTimeout.immediate,
  }) {
    pinLength = pin?.length;
  }

  bool enabled;
  String? pin;
  LockTimeout timeout;

  /// Null stands in for a legacy record whose length is unknown.
  int? pinLength;

  bool throwOnVerify = false;
  bool throwOnWrite = false;
  bool throwOnClear = false;
  Completer<bool>? verifyCompleter;

  /// The writes that reached storage, in the order they entered.
  final List<String> writes = [];

  /// Failure state the repo carries, like the real record does.
  int failedAttempts = 0;
  DateTime? retryAt;

  final List<Completer<void>> _holds = [];

  /// The next config write stops here until the test completes the answer.
  Completer<void> holdNextWrite() {
    final hold = Completer<void>();
    _holds.add(hold);
    return hold;
  }

  Future<void> _entered(String which) async {
    writes.add(which);
    if (_holds.isEmpty) return;
    await _holds.removeAt(0).future;
  }

  @override
  AppLockConfig get config => AppLockConfig(
    enabled: enabled,
    hasPin: pin != null,
    timeout: timeout,
    pinLength: pinLength,
    failedAttempts: failedAttempts,
    retryAt: retryAt,
  );

  @override
  Future<void> enable(String pin) async {
    if (throwOnWrite) throw const AppLockUnavailableException();
    await _entered('enable:$pin');
    this.pin = pin;
    pinLength = pin.length;
    enabled = true;
  }

  @override
  Future<void> changePin(String pin) async {
    if (throwOnWrite) throw const AppLockUnavailableException();
    await _entered('changePin:$pin');
    this.pin = pin;
    pinLength = pin.length;
  }

  @override
  Future<void> disable() async {
    if (throwOnWrite) throw const AppLockUnavailableException();
    await _entered('disable');
    pin = null;
    pinLength = null;
    enabled = false;
  }

  @override
  Future<bool> verify(String pin) {
    if (throwOnVerify) throw const AppLockUnavailableException();
    final completer = verifyCompleter;
    if (completer != null) return completer.future;
    return Future.value(this.pin == pin);
  }

  @override
  Future<void> setTimeout(LockTimeout timeout) async {
    if (throwOnWrite) throw const AppLockUnavailableException();
    await _entered('setTimeout:$timeout');
    this.timeout = timeout;
  }

  @override
  Future<DateTime?> recordFailure(DateTime now) async {
    await _entered('recordFailure');
    failedAttempts += 1;
    retryAt = pinRetryAt(failedAttempts, now);
    return retryAt;
  }

  @override
  Future<void> clearFailures() async {
    if (throwOnClear) throw const AppLockUnavailableException();
    await _entered('clearFailures');
    failedAttempts = 0;
    retryAt = null;
  }

  @override
  Future<void> settleAfterUnlock(String pin) async {
    if (throwOnClear) throw const AppLockUnavailableException();
    await _entered('settle:$pin');
    failedAttempts = 0;
    retryAt = null;
    pinLength ??= pin.length;
  }
}

class _FakeBiometrics implements BiometricAuth {
  bool available = true;
  BiometricResult result = const BiometricResult.success();
  Future<BiometricResult> Function()? onAuthenticate;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricResult> authenticate(String reason) {
    return onAuthenticate?.call() ?? Future.value(result);
  }
}

class _FakeClock extends Clock {
  _FakeClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

void main() {
  late _FakeAppLockRepo repo;
  late _FakeBiometrics biometrics;
  late _FakeClock clock;
  late ProviderContainer container;

  AppLockData data() => container.read(appLockProvider);
  AppLock notifier() => container.read(appLockProvider.notifier);

  Future<void> create({
    bool enabled = true,
    String? pin = '1234',
    LockTimeout timeout = LockTimeout.immediate,
  }) async {
    repo = _FakeAppLockRepo(enabled: enabled, pin: pin, timeout: timeout);
    biometrics = _FakeBiometrics();
    clock = _FakeClock(DateTime(2026, 1, 1, 12));
    container = ProviderContainer(
      overrides: [
        appLockRepoProvider.overrideWithValue(repo),
        biometricAuthProvider.overrideWithValue(biometrics),
        clockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(container.dispose);
    container.setupTestFor(appLockProvider);
    // The sensor check is scheduled after the first state.
    await Future<void>.delayed(Duration.zero);
  }

  group('cold start', () {
    test('opens locked when the lock is active', () async {
      await create();

      expect(data().isActive, isTrue);
      expect(data().isLocked, isTrue);
      expect(data().biometricsAvailable, isTrue);
    });

    test('opens straight into the app when the lock is off', () async {
      await create(enabled: false, pin: null);

      expect(data().isActive, isFalse);
      expect(data().isLocked, isFalse);
    });
  });

  group('PIN', () {
    test('a wrong PIN stays locked and counts the attempt', () async {
      await create();

      expect(await notifier().unlockWithPin('0000'), UnlockResult.wrongPin);
      expect(data().isLocked, isTrue);
      expect(data().failedAttempts, 1);
    });

    test('the right PIN unlocks and clears the attempts', () async {
      await create();
      await notifier().unlockWithPin('0000');

      expect(await notifier().unlockWithPin('1234'), UnlockResult.success);
      expect(data().isLocked, isFalse);
      expect(data().failedAttempts, 0);
    });

    test('checking from a screen does not unlock', () async {
      await create();

      expect(await notifier().checkPin('1234'), UnlockResult.success);
      expect(data().isLocked, isTrue);
    });

    test('an unavailable store reports instead of counting a guess', () async {
      await create();
      repo.throwOnVerify = true;

      expect(await notifier().unlockWithPin('1234'), UnlockResult.unavailable);
      expect(data().isLocked, isTrue);
      expect(data().failedAttempts, 0);
    });

    test('a second check while one is running is refused', () async {
      await create();
      repo.verifyCompleter = Completer<bool>();

      final first = notifier().unlockWithPin('1234');
      expect(await notifier().unlockWithPin('1234'), UnlockResult.busy);

      repo.verifyCompleter!.complete(true);
      expect(await first, UnlockResult.success);
    });

    test('the verdict does not wait for the failure record to clear', () async {
      await create();
      await notifier().unlockWithPin('0000');
      expect(repo.failedAttempts, 1);

      final held = repo.holdNextWrite();
      expect(await notifier().unlockWithPin('1234'), UnlockResult.success);
      expect(data().isLocked, isFalse);
      // The cleanup enters on a later turn — the unlock did not wait for
      // it — and is still held mid-flight, so the count has not landed.
      await Future<void>.delayed(Duration.zero);
      expect(repo.writes.last, 'settle:1234');
      expect(repo.failedAttempts, 1);

      held.complete();
      await pumpEventQueue();
      expect(repo.failedAttempts, 0);
      expect(data().failedAttempts, 0);
    });

    test('a failed cleanup still leaves the unlock standing', () async {
      await create();
      await notifier().unlockWithPin('0000');
      repo.throwOnClear = true;

      expect(await notifier().unlockWithPin('1234'), UnlockResult.success);
      expect(data().isLocked, isFalse);
      await pumpEventQueue();
    });

    test('a newer wrong guess is not wiped by the cleanup before it', () async {
      await create();
      final held = repo.holdNextWrite();

      // A correct entry queues its cleanup; the write is held mid-flight.
      expect(await notifier().checkPin('1234'), UnlockResult.success);
      await Future<void>.delayed(Duration.zero);
      expect(repo.writes, ['settle:1234']);

      // A wrong guess lands while the cleanup is still held. It has to
      // queue behind it: a clear that completed last would wipe the
      // failure the newer guess just earned.
      final wrong = notifier().unlockWithPin('0000');
      await Future<void>.delayed(Duration.zero);
      expect(repo.failedAttempts, 0);

      held.complete();
      expect(await wrong, UnlockResult.wrongPin);
      expect(repo.failedAttempts, 1);
      expect(repo.writes, ['settle:1234', 'recordFailure']);
    });

    test('the right PIN heals a legacy length', () async {
      await create();
      repo.pinLength = null;
      container.invalidate(appLockProvider);
      await Future<void>.delayed(Duration.zero);
      expect(data().pinLength, isNull);

      expect(await notifier().unlockWithPin('1234'), UnlockResult.success);
      await pumpEventQueue();
      // The settle learned the true length from the PIN that opened it,
      // and the state mirrors it so the next gate auto-submits again.
      expect(repo.pinLength, 4);
      expect(data().pinLength, 4);
    });
  });

  group('attempt throttle', () {
    test(
      'the fifth wrong PIN starts a wait and blocks even the right one',
      () async {
        await create();

        for (var i = 0; i < freePinAttempts; i++) {
          expect(await notifier().unlockWithPin('0000'), UnlockResult.wrongPin);
        }
        expect(data().retryAt, isNull);

        expect(await notifier().unlockWithPin('0000'), UnlockResult.wrongPin);
        expect(data().failedAttempts, freePinAttempts + 1);
        expect(data().retryAt, clock.now().add(shortPinLockout));

        expect(await notifier().unlockWithPin('1234'), UnlockResult.throttled);
        expect(data().failedAttempts, freePinAttempts + 1);
      },
    );

    test('the right PIN works again once the wait has passed', () async {
      await create();
      for (var i = 0; i <= freePinAttempts; i++) {
        await notifier().unlockWithPin('0000');
      }

      clock.advance(shortPinLockout);

      expect(await notifier().unlockWithPin('1234'), UnlockResult.success);
      expect(data().isLocked, isFalse);
      expect(data().retryAt, isNull);
    });

    test('the counter lives in the repo, so a restart keeps it', () async {
      await create();
      for (var i = 0; i <= freePinAttempts; i++) {
        await notifier().unlockWithPin('0000');
      }
      expect(repo.failedAttempts, freePinAttempts + 1);
      expect(repo.retryAt, isNotNull);

      // A new container over the same repo: what a process restart reads.
      final restarted = ProviderContainer(
        overrides: [
          appLockRepoProvider.overrideWithValue(repo),
          biometricAuthProvider.overrideWithValue(biometrics),
          clockProvider.overrideWithValue(clock),
        ],
      );
      addTearDown(restarted.dispose);

      final carried = restarted.read(appLockProvider);
      expect(carried.failedAttempts, freePinAttempts + 1);
      expect(carried.retryAt, isNotNull);
      expect(carried.isThrottledAt(clock.now()), isTrue);
    });

    test('the waits grow with the run of wrong PINs', () {
      final now = DateTime(2026, 1, 1);

      expect(pinRetryAt(freePinAttempts, now), isNull);
      expect(pinRetryAt(freePinAttempts + 1, now), now.add(shortPinLockout));
      expect(pinRetryAt(7, now), now.add(shortPinLockout));
      expect(pinRetryAt(8, now), now.add(longPinLockout));
      expect(pinRetryAt(20, now), now.add(longPinLockout));
    });
  });

  group('lifecycle', () {
    test('immediate timeout locks as soon as the app is paused', () async {
      await create();
      await notifier().unlockWithPin('1234');

      notifier().onAppPaused();
      expect(data().isLocked, isTrue);
    });

    test('a timed timeout waits out its grace on resume', () async {
      await create(timeout: LockTimeout.minutes1);
      await notifier().unlockWithPin('1234');

      notifier().onAppPaused();
      clock.advance(const Duration(seconds: 59));
      notifier().onAppResumed();
      expect(data().isLocked, isFalse);

      notifier().onAppPaused();
      clock.advance(const Duration(seconds: 61));
      notifier().onAppResumed();
      expect(data().isLocked, isTrue);
    });

    test(
      'never keeps the session through a long stay in the background',
      () async {
        await create(timeout: LockTimeout.never);
        await notifier().unlockWithPin('1234');

        notifier().onAppPaused();
        clock.advance(const Duration(days: 1));
        notifier().onAppResumed();

        expect(data().isLocked, isFalse);
      },
    );

    test('the prompt\'s own pause does not lock an open app', () async {
      await create();
      await notifier().unlockWithPin('1234');

      final prompt = Completer<BiometricResult>();
      biometrics.onAuthenticate = () => prompt.future;
      final pending = notifier().unlockWithBiometrics('reason');
      await Future<void>.delayed(Duration.zero);

      notifier().onAppPaused();
      expect(data().isLocked, isFalse);

      prompt.complete(const BiometricResult.success());
      expect(await pending, UnlockResult.success);
      expect(data().isLocked, isFalse);
    });

    test(
      'a picker round-trip does not lock under the immediate timeout',
      () async {
        await create();
        await notifier().unlockWithPin('1234');

        notifier().beginExternalFlow();
        notifier().onAppPaused();
        clock.advance(const Duration(seconds: 8));
        notifier().endExternalFlow();
        notifier().onAppResumed();

        expect(data().isLocked, isFalse);
      },
    );

    test(
      'the picker result arriving after the resume keeps the session',
      () async {
        await create();
        await notifier().unlockWithPin('1234');

        // The platform result and the lifecycle resume arrive in an order the
        // app does not control; either way the trip belongs to the session.
        notifier().beginExternalFlow();
        notifier().onAppPaused();
        clock.advance(const Duration(seconds: 5));
        notifier().onAppResumed();
        notifier().endExternalFlow();

        expect(data().isLocked, isFalse);
      },
    );

    test('a picker left open past the ceiling locks on return', () async {
      await create();
      await notifier().unlockWithPin('1234');

      notifier().beginExternalFlow();
      notifier().onAppPaused();
      clock.advance(externalFlowCeiling + const Duration(seconds: 1));
      notifier().endExternalFlow();
      notifier().onAppResumed();

      expect(data().isLocked, isTrue);
    });

    test('a pause after the flow ended still locks immediately', () async {
      await create();
      await notifier().unlockWithPin('1234');

      notifier().beginExternalFlow();
      notifier().endExternalFlow();

      notifier().onAppPaused();
      expect(data().isLocked, isTrue);
    });

    test('a timed policy keeps its own grace during a picker trip', () async {
      await create(timeout: LockTimeout.seconds30);
      await notifier().unlockWithPin('1234');

      notifier().beginExternalFlow();
      notifier().onAppPaused();
      clock.advance(const Duration(seconds: 31));
      notifier().endExternalFlow();
      notifier().onAppResumed();

      expect(data().isLocked, isTrue);
    });
  });

  group('biometrics', () {
    test('a successful prompt unlocks', () async {
      await create();

      expect(
        await notifier().unlockWithBiometrics('reason'),
        UnlockResult.success,
      );
      expect(data().isLocked, isFalse);
    });

    test('a biometric unlock clears the failure record too', () async {
      await create();
      await notifier().unlockWithPin('0000');
      expect(repo.failedAttempts, 1);

      expect(
        await notifier().unlockWithBiometrics('reason'),
        UnlockResult.success,
      );
      await pumpEventQueue();
      // The sensor answered for the PIN: the throttle it satisfied must
      // not outlive the unlock and greet the next cold start.
      expect(repo.failedAttempts, 0);
      expect(data().failedAttempts, 0);
    });

    test('a canceled prompt leaves the lock up', () async {
      await create();
      biometrics.result = const BiometricResult.failed(
        BiometricFailure.canceled,
      );

      expect(
        await notifier().unlockWithBiometrics('reason'),
        UnlockResult.canceled,
      );
      expect(data().isLocked, isTrue);
    });

    test('a device lockout is reported so the PIN can take over', () async {
      await create();
      biometrics.result = const BiometricResult.failed(
        BiometricFailure.lockout,
      );

      expect(
        await notifier().unlockWithBiometrics('reason'),
        UnlockResult.biometricLockout,
      );
    });

    test('an unavailable sensor is reported', () async {
      await create();
      biometrics.result = const BiometricResult.failed(
        BiometricFailure.unavailable,
      );

      expect(
        await notifier().unlockWithBiometrics('reason'),
        UnlockResult.unavailable,
      );
    });
  });

  group('settings changes', () {
    test('enable, change and disable follow the repository', () async {
      await create(enabled: false, pin: null);
      expect(data().isActive, isFalse);

      await notifier().enable('1111');
      expect(data().isActive, isTrue);
      expect(data().isLocked, isFalse);
      expect(repo.pin, '1111');

      await notifier().changePin('2222');
      expect(repo.pin, '2222');

      await notifier().disable();
      expect(data().isActive, isFalse);
      expect(data().isLocked, isFalse);
      expect(repo.pin, isNull);
    });

    test('a failed write leaves the state as it was', () async {
      await create(enabled: false, pin: null);
      repo.throwOnWrite = true;

      await expectLater(
        notifier().enable('1111'),
        throwsA(isA<AppLockUnavailableException>()),
      );
      expect(data().isActive, isFalse);
    });

    test('a new timeout is stored and shown', () async {
      await create();

      await notifier().setTimeout(LockTimeout.minutes5);

      expect(data().timeout, LockTimeout.minutes5);
      expect(repo.timeout, LockTimeout.minutes5);
    });

    test('a second toggle waits for the first to reach storage', () async {
      await create(enabled: false, pin: null);
      final held = repo.holdNextWrite();

      // Both taps land while the switch still reads off. They used to put two
      // PINs on their way to storage at once, and whichever arrived last owned
      // the lock: the person who typed the first PIN was locked out of a lock
      // they believe they set once.
      final first = notifier().enable('1111');
      final second = notifier().enable('2222');
      await Future<void>.delayed(Duration.zero);

      expect(repo.writes, ['enable:1111']);
      expect(repo.pin, isNull);

      held.complete();
      await first;
      await second;

      expect(repo.writes, ['enable:1111', 'enable:2222']);
      expect(repo.pin, '2222');
      expect(data().isActive, isTrue);
    });
  });
}
