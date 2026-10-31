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
  });

  bool enabled;
  String? pin;
  LockTimeout timeout;

  bool throwOnVerify = false;
  bool throwOnWrite = false;
  Completer<bool>? verifyCompleter;

  @override
  AppLockConfig get config =>
      AppLockConfig(enabled: enabled, hasPin: pin != null, timeout: timeout);

  @override
  Future<void> enable(String pin) async {
    if (throwOnWrite) throw const AppLockUnavailableException();
    this.pin = pin;
    enabled = true;
  }

  @override
  Future<void> changePin(String pin) async {
    if (throwOnWrite) throw const AppLockUnavailableException();
    this.pin = pin;
  }

  @override
  Future<void> disable() async {
    if (throwOnWrite) throw const AppLockUnavailableException();
    pin = null;
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
    this.timeout = timeout;
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
  });
}
