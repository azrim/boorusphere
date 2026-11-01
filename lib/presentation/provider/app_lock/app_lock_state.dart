import 'dart:async';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/domain/repository/app_lock_repo.dart';
import 'package:boorusphere/presentation/provider/app_lock/biometric_auth.dart';
import 'package:boorusphere/presentation/provider/app_lock/clock.dart';
import 'package:boorusphere/presentation/provider/app_lock/entity/app_lock_data.dart';
import 'package:boorusphere/presentation/provider/app_lock/lockout.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_lock_state.g.dart';

enum UnlockResult {
  success,
  wrongPin,

  /// Too many wrong PINs; [AppLockData.retryAt] says when to try again.
  throttled,
  canceled,

  /// The device stopped accepting biometrics until another method opens it.
  biometricLockout,
  failed,
  unavailable,
  busy,
}

/// Decides when the app is covered by the lock and checks the ways in.
///
/// Lives for the whole session: the attempt counter and the locked state must
/// survive navigation, and the lock screen is shown by the app shell rather
/// than a route so the page under it keeps its state.
@Riverpod(keepAlive: true)
class AppLock extends _$AppLock {
  bool _busy = false;

  /// Set while the system prompt is on screen. The prompt pauses the app on
  /// Android, and that pause must not be read as the user leaving it.
  bool _authenticating = false;

  /// When the app went to the background, while a timed lock is armed.
  DateTime? _pausedAt;

  /// Set while the app itself has a system surface open, such as the file
  /// picker or the share sheet. The app pauses for it, but the user has not
  /// left, so an immediate lock waits for the round-trip to finish.
  DateTime? _externalFlowStartedAt;

  /// Whether the pause being handled belongs to [_externalFlowStartedAt].
  bool _pausedDuringExternalFlow = false;

  Timer? _retryTimer;

  @override
  AppLockData build() {
    final config = ref.watch(appLockRepoProvider).config;
    ref.onDispose(() => _retryTimer?.cancel());

    // Checking the sensor talks to the platform, so it happens after the
    // first state exists instead of delaying the frame.
    unawaited(Future.microtask(refreshBiometrics));

    return AppLockData(
      enabled: config.enabled,
      hasPin: config.hasPin,
      timeout: config.timeout,
      // A cold start begins behind the lock: unlike a resume, there is no
      // session here to keep open.
      locked: config.isActive,
    );
  }

  DateTime _now() => ref.read(clockProvider).now();

  Future<void> refreshBiometrics() async {
    try {
      final available = await ref.read(biometricAuthProvider).isAvailable();
      if (!ref.mounted || state.biometricsAvailable == available) return;
      state = state.copyWith(biometricsAvailable: available);
    } catch (e, stack) {
      mainLog.w('App lock: failed to check biometrics', e, stack);
    }
  }

  /// Opens the app with the PIN.
  Future<UnlockResult> unlockWithPin(String pin) async {
    if (!state.isActive) {
      _unlock();
      return UnlockResult.success;
    }

    final result = await checkPin(pin);
    if (result == UnlockResult.success) _unlock();
    return result;
  }

  /// Checks the PIN without changing the lock, for a screen that asks for it
  /// while the app is already open.
  ///
  /// Shares the attempt counter with the lock screen: one list of guesses,
  /// whichever screen it was typed on.
  Future<UnlockResult> checkPin(String pin) async {
    if (!state.hasPin) return UnlockResult.success;
    if (_busy) return UnlockResult.busy;

    final now = _now();
    if (state.isThrottledAt(now)) return UnlockResult.throttled;
    if (state.retryAt != null) {
      // The wait has passed but the timer has not run yet; clear it before a
      // fresh comparison starts.
      state = state.copyWith(retryAt: null);
    }

    _busy = true;
    try {
      final ok = await ref.read(appLockRepoProvider).verify(pin);
      if (!ref.mounted) return UnlockResult.unavailable;

      if (ok) {
        _clearFailures();
        return UnlockResult.success;
      }

      _recordFailure(_now());
      return UnlockResult.wrongPin;
    } on AppLockUnavailableException catch (e, stack) {
      mainLog.e('App lock: the PIN could not be checked', e, stack);
      return UnlockResult.unavailable;
    } catch (e, stack) {
      mainLog.e('App lock: the PIN check failed', e, stack);
      return UnlockResult.unavailable;
    } finally {
      _busy = false;
    }
  }

  /// Opens the app with the device biometric prompt.
  Future<UnlockResult> unlockWithBiometrics(String reason) async {
    if (!state.isActive) {
      _unlock();
      return UnlockResult.success;
    }
    if (_busy) return UnlockResult.busy;

    // No PIN throttle here: the system sensor has its own lockout, and the
    // PIN stays available while the sensor recovers.
    _busy = true;
    _authenticating = true;
    try {
      final result = await ref.read(biometricAuthProvider).authenticate(reason);
      if (!ref.mounted) return UnlockResult.unavailable;

      if (result.success) {
        _unlock();
        return UnlockResult.success;
      }

      return switch (result.failure) {
        BiometricFailure.canceled => UnlockResult.canceled,
        BiometricFailure.lockout => UnlockResult.biometricLockout,
        BiometricFailure.unavailable => UnlockResult.unavailable,
        BiometricFailure.failed || null => UnlockResult.failed,
      };
    } catch (e, stack) {
      mainLog.e('App lock: the biometric prompt failed', e, stack);
      return UnlockResult.unavailable;
    } finally {
      _busy = false;
      _authenticating = false;
    }
  }

  /// Marks the start of a system surface the app opened itself, such as the
  /// file picker.
  ///
  /// Call it right before awaiting the platform call and release it with
  /// [endExternalFlow] when the call returns. The app pauses for that surface
  /// like for any other activity, but the user has not left; an immediate
  /// lock waits for the round-trip instead of covering the screen on return.
  void beginExternalFlow() {
    _externalFlowStartedAt = _now();
  }

  void endExternalFlow() {
    _externalFlowStartedAt = null;
  }

  void onAppPaused() {
    if (!state.isActive || state.locked) return;
    // The biometric sheet is part of the app, not a departure from it.
    if (_authenticating) return;

    // The pause belongs to a surface the app opened itself. Remember the
    // moment so a round-trip that runs past [externalFlowCeiling] still locks
    // on resume.
    if (_externalFlowStartedAt != null) {
      _pausedDuringExternalFlow = true;
      _pausedAt = _now();
      return;
    }
    _pausedDuringExternalFlow = false;

    switch (state.timeout) {
      case LockTimeout.immediate:
        _lock();
      case LockTimeout.never:
        _pausedAt = null;
      case LockTimeout.seconds30:
      case LockTimeout.minutes1:
      case LockTimeout.minutes5:
        _pausedAt = _now();
    }
  }

  void onAppResumed() {
    final pausedAt = _pausedAt;
    final pausedDuringExternalFlow = _pausedDuringExternalFlow;
    _pausedAt = null;
    _pausedDuringExternalFlow = false;
    unawaited(refreshBiometrics());

    if (pausedAt == null || !state.isActive || state.locked) return;

    final away = _now().difference(pausedAt);
    // A quick trip through a picker is still the session the user started,
    // even under the immediate policy. A long one means they left it there.
    if (pausedDuringExternalFlow &&
        state.timeout == LockTimeout.immediate &&
        !away.isNegative &&
        away <= externalFlowCeiling) {
      return;
    }

    final grace = state.timeout.duration;
    if (grace == null) return;
    if (!away.isNegative && away >= grace) _lock();
  }

  Future<void> enable(String pin) async {
    await ref.read(appLockRepoProvider).enable(pin);
    if (!ref.mounted) return;

    _clearFailures();
    state = state.copyWith(enabled: true, hasPin: true, locked: false);
  }

  Future<void> changePin(String pin) async {
    await ref.read(appLockRepoProvider).changePin(pin);
    if (!ref.mounted) return;

    _clearFailures();
    state = state.copyWith(hasPin: true);
  }

  Future<void> disable() async {
    await ref.read(appLockRepoProvider).disable();
    if (!ref.mounted) return;

    _clearFailures();
    _pausedAt = null;
    _pausedDuringExternalFlow = false;
    state = state.copyWith(enabled: false, hasPin: false, locked: false);
  }

  Future<void> setTimeout(LockTimeout timeout) async {
    await ref.read(appLockRepoProvider).setTimeout(timeout);
    if (!ref.mounted) return;

    state = state.copyWith(timeout: timeout);
    if (timeout == LockTimeout.never) _pausedAt = null;
  }

  void _unlock() {
    _pausedAt = null;
    state = state.copyWith(locked: false, failedAttempts: 0, retryAt: null);
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _lock() {
    _pausedAt = null;
    state = state.copyWith(locked: true);
  }

  void _recordFailure(DateTime now) {
    final attempts = state.failedAttempts + 1;
    final retryAt = pinRetryAt(attempts, now);
    state = state.copyWith(failedAttempts: attempts, retryAt: retryAt);

    _retryTimer?.cancel();
    if (retryAt == null) {
      _retryTimer = null;
      return;
    }

    final wait = retryAt.difference(now);
    _retryTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _retryTimer = null;
      if (!ref.mounted) return;
      state = state.copyWith(retryAt: null);
    });
  }

  void _clearFailures() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (state.failedAttempts == 0 && state.retryAt == null) return;
    state = state.copyWith(failedAttempts: 0, retryAt: null);
  }
}
