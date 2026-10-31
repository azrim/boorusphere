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
  });

  final bool enabled;
  final bool hasPin;
  final LockTimeout timeout;

  bool get isActive => enabled && hasPin;

  AppLockConfig copyWith({bool? enabled, bool? hasPin, LockTimeout? timeout}) {
    return AppLockConfig(
      enabled: enabled ?? this.enabled,
      hasPin: hasPin ?? this.hasPin,
      timeout: timeout ?? this.timeout,
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
}
