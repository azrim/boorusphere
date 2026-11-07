import 'dart:async';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/domain/repository/app_lock_repo.dart';
import 'package:boorusphere/presentation/provider/app_lock/biometric_auth.dart';
import 'package:boorusphere/presentation/provider/app_lock/clock.dart';
import 'package:boorusphere/presentation/provider/app_lock/entity/app_lock_data.dart';
import 'package:boorusphere/presentation/provider/app_lock/lockout.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:boorusphere/utils/serial_queue.dart';
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

  /// Lock config writes, one at a time.
  final _configWrites = SerialQueue();

  /// Set while the system prompt is on screen. The prompt pauses the app on
  /// Android, and that pause must not be read as the user leaving it.
  bool _authenticating = false;

  /// Whether the pause being handled belongs to the biometric prompt. The
  /// plugin keeps the sheet across a pause, so an absence with it open is
  /// bounded by [authFlowCeiling] instead of ignored outright.
  bool _pausedDuringAuth = false;

  /// Bumped when a long absence locks the app out from under a pending
  /// prompt. A match that landed in the same instant carries the old epoch
  /// and must not open a lock the absence just earned.
  int _authEpoch = 0;

  /// When the app went to the background, while a timed lock is armed.
  DateTime? _pausedAt;

  /// Set while the app itself has a system surface open, such as the file
  /// picker or the share sheet. The app pauses for it, but the user has not
  /// left, so an immediate lock waits for the round-trip to finish.
  DateTime? _externalFlowStartedAt;

  /// Whether the pause being handled belongs to [_externalFlowStartedAt].
  bool _pausedDuringExternalFlow = false;

  Timer? _retryTimer;

  /// End of the live wait on [Clock.elapsed]. The wall clock in the record is
  /// only its fallback across a restart: moving the system clock must not end
  /// a wait the process is still counting.
  Duration? _retryUntil;

  @override
  AppLockData build() {
    final config = ref.watch(appLockRepoProvider).config;
    ref.onDispose(() => _retryTimer?.cancel());

    // Checking the sensor talks to the platform, so it happens after the
    // first state exists instead of delaying the frame.
    unawaited(Future.microtask(refreshBiometrics));

    // The failure count lives in the record next to the verifier, so a run
    // of guesses costs the same after a restart. A carried wait is the one
    // case that has to trust the wall clock: the monotonic count starts over
    // with the process. One whose deadline already passed is no wait at all.
    final now = _now();
    final retryAt = config.retryAt;
    final liveRetryAt = retryAt != null && retryAt.isAfter(now)
        ? retryAt
        : null;
    if (liveRetryAt != null) {
      _armRetryTimer(liveRetryAt.difference(now));
    }

    return AppLockData(
      enabled: config.enabled,
      hasPin: config.hasPin,
      timeout: config.timeout,
      pinLength: config.pinLength,
      failedAttempts: config.failedAttempts,
      retryAt: liveRetryAt,
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

    if (_isThrottled()) return UnlockResult.throttled;
    if (state.retryAt != null) {
      // The wait has passed but the timer has not run yet; clear it before a
      // fresh comparison starts.
      _clearRetry();
      state = state.copyWith(retryAt: null);
    }

    _busy = true;
    try {
      final repo = ref.read(appLockRepoProvider);
      final ok = await repo.verify(pin);
      if (!ref.mounted) return UnlockResult.unavailable;

      if (ok) {
        // The verdict is earned the moment the comparison answers. Clearing
        // the failure record and healing a legacy length are housekeeping:
        // they must not keep the user waiting on a storage round-trip, and
        // a failed cleanup must not turn a correct PIN into an error.
        _settle(() => ref.read(appLockRepoProvider).settleAfterUnlock(pin));
        return UnlockResult.success;
      }

      // The guess is counted even when storage refuses the write (the repo
      // adopts it in memory then). Queuing the record behind any cleanup
      // still in flight keeps a backgrounded clear from wiping a newer
      // failure: whoever asked first writes first.
      final retryAt = await _config(() => repo.recordFailure(_now()));
      if (!ref.mounted) return UnlockResult.wrongPin;
      _syncRecord();
      _armRetryAfterFailure(retryAt);
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
    final epoch = _authEpoch;
    _busy = true;
    _authenticating = true;
    try {
      final result = await ref.read(biometricAuthProvider).authenticate(reason);
      if (!ref.mounted) return UnlockResult.unavailable;
      if (epoch != _authEpoch) return UnlockResult.canceled;

      if (result.success) {
        // The sensor answered for the PIN, so the same failure record has
        // to clear: a throttle the user already satisfied must not outlive
        // the unlock and greet the next cold start.
        _settle(() => ref.read(appLockRepoProvider).clearFailures());
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
    // The biometric sheet is part of the app, not a departure from it — but
    // the plugin keeps the sheet across the pause, so an absence with it
    // open is bounded on resume instead of ignored outright.
    if (_authenticating) {
      _pausedDuringAuth = true;
      _pausedAt = _now();
      return;
    }

    // The pause belongs to a surface the app opened itself. Remember the
    // moment so a round-trip that runs past [externalFlowCeiling] still locks
    // on resume.
    if (_externalFlowStartedAt != null) {
      _pausedDuringExternalFlow = true;
      _pausedAt = _now();
      return;
    }
    _pausedDuringExternalFlow = false;
    _pausedDuringAuth = false;

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
    final pausedDuringAuth = _pausedDuringAuth;
    _pausedAt = null;
    _pausedDuringExternalFlow = false;
    _pausedDuringAuth = false;
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
    // The prompt's own pause is quick by nature. A long absence with the
    // sheet still open means the user walked away from an open gate, which
    // is a departure under any policy that locks on resume at all.
    if (pausedDuringAuth &&
        state.timeout == LockTimeout.immediate &&
        !away.isNegative &&
        away <= authFlowCeiling) {
      return;
    }

    final grace = state.timeout.duration;
    if (grace == null) return;
    if (!away.isNegative && away >= grace) {
      if (_authenticating) {
        // The plugin re-shows the kept-alive sheet on resume, so it has to
        // be taken down explicitly or it comes back above the lock cover.
        // Retire the epoch too: a match that landed in the same instant as
        // the resume must not open a lock the absence just earned.
        _authEpoch++;
        unawaited(ref.read(biometricAuthProvider).cancel());
      }
      _lock();
    }
  }

  /// Runs one [enable], [changePin], [disable] or [setTimeout] after another.
  ///
  /// The settings page stays tappable while a write is in flight and its
  /// switch still shows the value from before, so a second toggle can open a
  /// second PIN entry. Whichever write reaches secure storage last owns the
  /// lock, and someone who typed the earlier PIN is then locked out of a lock
  /// they believe they set once.
  ///
  /// The attempt ledger joins the same queue so a cleanup and a newer guess
  /// cannot overtake each other on the way to the record.
  Future<T> _config<T>(Future<T> Function() write) {
    return _configWrites.run(write);
  }

  /// Queues post-unlock housekeeping and mirrors the ledger once it lands.
  ///
  /// Best-effort by design: the unlock already happened, so a write that
  /// fails here is logged, not reported. The repo keeps the cleared count in
  /// memory regardless, and the next successful write carries it along.
  void _settle(Future<void> Function() write) {
    unawaited(
      _config(write)
          .then((_) {
            if (ref.mounted) _syncRecord();
          })
          .catchError((Object e, StackTrace stack) {
            mainLog.w(
              'App lock: the unlock ledger could not be settled',
              e,
              stack,
            );
          }),
    );
  }

  Future<void> enable(String pin) {
    return _config(() async {
      await ref.read(appLockRepoProvider).enable(pin);
      if (!ref.mounted) return;

      _clearRetry();
      state = state.copyWith(
        enabled: true,
        hasPin: true,
        locked: false,
        pinLength: pin.length,
        failedAttempts: 0,
        retryAt: null,
      );
    });
  }

  Future<void> changePin(String pin) {
    return _config(() async {
      await ref.read(appLockRepoProvider).changePin(pin);
      if (!ref.mounted) return;

      _clearRetry();
      state = state.copyWith(
        hasPin: true,
        pinLength: pin.length,
        failedAttempts: 0,
        retryAt: null,
      );
    });
  }

  Future<void> disable() {
    return _config(() async {
      await ref.read(appLockRepoProvider).disable();
      if (!ref.mounted) return;

      _pausedAt = null;
      _pausedDuringExternalFlow = false;
      _pausedDuringAuth = false;
      _clearRetry();
      state = state.copyWith(
        enabled: false,
        hasPin: false,
        locked: false,
        failedAttempts: 0,
        retryAt: null,
      );
    });
  }

  Future<void> setTimeout(LockTimeout timeout) {
    return _config(() async {
      await ref.read(appLockRepoProvider).setTimeout(timeout);
      if (!ref.mounted) return;

      state = state.copyWith(timeout: timeout);
      if (timeout == LockTimeout.never) _pausedAt = null;
    });
  }

  void _unlock() {
    _pausedAt = null;
    _pausedDuringAuth = false;
    _clearRetry();
    state = state.copyWith(locked: false, failedAttempts: 0, retryAt: null);
  }

  void _lock() {
    _pausedAt = null;
    state = state.copyWith(locked: true);
  }

  /// Mirrors the repo's ledger fields into the state, after a write: the
  /// failure count, the wait it earned, and a length the settle healed.
  void _syncRecord() {
    final config = ref.read(appLockRepoProvider).config;
    state = state.copyWith(
      failedAttempts: config.failedAttempts,
      retryAt: config.retryAt,
      pinLength: config.pinLength,
    );
  }

  /// Schedules the moment the throttle clears; the repo owns the record, this
  /// only moves the countdown on screen.
  void _armRetryAfterFailure(DateTime? retryAt) {
    _clearRetry();
    if (retryAt == null) return;
    _armRetryTimer(retryAt.difference(_now()));
  }

  /// Anchors [wait] on the monotonic clock and keeps the displayed deadline
  /// in step with it once a second.
  ///
  /// The record holds an absolute wall-clock deadline, but that is also the
  /// one input the user can move. Republishing it from the monotonic count
  /// means a clock jump neither shortens nor stretches the wait, and the line
  /// on screen never shows a time the lock no longer believes.
  void _armRetryTimer(Duration wait) {
    final bounded = wait.isNegative ? Duration.zero : wait;
    _retryUntil = ref.read(clockProvider).elapsed() + bounded;
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!ref.mounted) return;
      final until = _retryUntil;
      if (until == null) return;
      final left = until - ref.read(clockProvider).elapsed();
      if (left <= Duration.zero) {
        _clearRetry();
        state = state.copyWith(retryAt: null);
        return;
      }
      state = state.copyWith(retryAt: _now().add(left));
    });
  }

  void _clearRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryUntil = null;
  }

  /// Whether the live wait still holds. The monotonic anchor is the verdict;
  /// the wall-clock field is only consulted when there is no anchor.
  bool _isThrottled() {
    final until = _retryUntil;
    if (until != null) return ref.read(clockProvider).elapsed() < until;
    return state.isThrottledAt(_now());
  }
}
