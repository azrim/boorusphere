/// How many digits a PIN may hold. The setup field takes up to this many and
/// the gate's pad submits at whatever length was registered.
const int maxPinLength = 8;

/// The smallest PIN the setup accepts.
const int minPinLength = 4;

/// How long the app may stay in the background before it is locked again.
///
/// [never] still locks on a cold start: the cold start lock is what keeps the
/// app closed to someone who picks up the device, while this timeout only
/// decides how quickly a session that is already open closes again.
enum LockTimeout {
  immediate,
  seconds30,
  minutes1,
  minutes5,
  never;

  /// The grace period, or null when a resume must not lock at all.
  Duration? get duration => switch (this) {
    immediate => Duration.zero,
    seconds30 => const Duration(seconds: 30),
    minutes1 => const Duration(minutes: 1),
    minutes5 => const Duration(minutes: 5),
    never => null,
  };

  static LockTimeout fromName(Object? name) {
    return LockTimeout.values.firstWhere(
      (it) => it.name == name,
      orElse: () => LockTimeout.immediate,
    );
  }
}

/// The persisted lock configuration, without the secret that verifies a PIN.
class AppLockConfig {
  const AppLockConfig({
    this.enabled = false,
    this.hasPin = false,
    this.timeout = LockTimeout.immediate,
    this.pinLength,
    this.failedAttempts = 0,
    this.retryAt,
  });

  final bool enabled;
  final bool hasPin;
  final LockTimeout timeout;

  /// How many digits the registered PIN runs; the gate sizes its dots row and
  /// its auto-submit by it. Null when the record predates the field or carries
  /// an impossible value: the true length is unknown, so the gate takes up to
  /// [maxPinLength] digits and submits by hand until a correct entry heals it.
  final int? pinLength;

  /// Wrong PINs on record. Carried across restarts, so killing the app does
  /// not reset the cost of a run of guesses.
  final int failedAttempts;

  /// When the next PIN may be tried, or null while attempts are still free.
  final DateTime? retryAt;

  bool get isActive => enabled && hasPin;

  AppLockConfig copyWith({
    bool? enabled,
    bool? hasPin,
    LockTimeout? timeout,
    int? pinLength,
    int? failedAttempts,
    DateTime? retryAt,
  }) {
    return AppLockConfig(
      enabled: enabled ?? this.enabled,
      hasPin: hasPin ?? this.hasPin,
      timeout: timeout ?? this.timeout,
      pinLength: pinLength ?? this.pinLength,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      retryAt: retryAt ?? this.retryAt,
    );
  }
}

/// Raised when the secure store cannot be read or written.
class AppLockUnavailableException implements Exception {
  const AppLockUnavailableException();

  @override
  String toString() => 'The app lock secure storage is unavailable.';
}

/// Stores the PIN verifier and the lock preferences.
///
/// The settings live next to the PIN instead of the settings box on purpose:
/// an archive can restore settings, and a restored "lock enabled" without the
/// matching PIN would leave the app locked with no way in.
abstract interface class AppLockRepo {
  AppLockConfig get config;

  /// Replaces the PIN and enables the lock in one step.
  Future<void> enable(String pin);

  /// Replaces the PIN, keeping the lock enabled.
  Future<void> changePin(String pin);

  /// Removes the PIN and disables the lock.
  Future<void> disable();

  Future<bool> verify(String pin);

  Future<void> setTimeout(LockTimeout timeout);

  /// Records a wrong guess and reads back the wait it earned, or null while
  /// attempts are still free. Kept on the repo so the count survives a
  /// restart next to the verifier it protects.
  Future<DateTime?> recordFailure(DateTime now);

  /// Clears the failure count and any wait, after a correct entry.
  Future<void> clearFailures();

  /// Housekeeping after a correct PIN entry: clears the failure record and
  /// heals a length the record never knew. Best-effort — the verdict already
  /// stands, so a refused write degrades to memory instead of surfacing.
  Future<void> settleAfterUnlock(String pin);
}
