import 'package:boorusphere/domain/repository/app_lock_repo.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_lock_data.freezed.dart';

/// What the lock is doing right now, on top of the persisted preferences.
@freezed
abstract class AppLockData with _$AppLockData {
  const factory AppLockData({
    @Default(false) bool enabled,
    @Default(false) bool hasPin,
    @Default(LockTimeout.immediate) LockTimeout timeout,
    @Default(maxPinLength) int pinLength,
    @Default(false) bool locked,

    /// Wrong PINs in this session, used to space out the retries.
    @Default(0) int failedAttempts,

    /// Set while a retry has to wait; null once the wait is over.
    DateTime? retryAt,

    /// Whether the device can answer a biometric prompt at this moment.
    @Default(false) bool biometricsAvailable,
  }) = _AppLockData;

  const AppLockData._();

  bool get isActive => enabled && hasPin;

  bool get isLocked => isActive && locked;

  bool isThrottledAt(DateTime now) {
    final at = retryAt;
    return at != null && at.isAfter(now);
  }

  /// Whole seconds left before another PIN can be tried, rounded up so the
  /// countdown does not show zero while the wait still has time left.
  int retrySecondsAt(DateTime now) {
    final at = retryAt;
    if (at == null) return 0;
    final left = at.difference(now).inMilliseconds;
    if (left <= 0) return 0;
    return (left / 1000).ceil();
  }
}
