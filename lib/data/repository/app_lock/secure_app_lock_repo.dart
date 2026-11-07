import 'dart:convert';
import 'dart:isolate';

import 'package:boorusphere/data/repository/app_lock/native_pin_kdf.dart';
import 'package:boorusphere/data/repository/app_lock/pin_hash.dart';
import 'package:boorusphere/data/repository/app_lock/secret_store.dart';
import 'package:boorusphere/domain/repository/app_lock_repo.dart';
import 'package:boorusphere/presentation/provider/app_lock/lockout.dart';
import 'package:boorusphere/utils/logger.dart';

/// The lock configuration and its verifier, stored as one encrypted record.
///
/// Kept out of the settings box so an archive cannot turn the lock on without
/// carrying the PIN that opens it, and so the settings export never sees the
/// verifier.
class SecureAppLockRepo implements AppLockRepo {
  SecureAppLockRepo._(this._store, this._config, this._pin, this._iterations);

  static const String storageKey = 'app_lock_v1';
  static const int schema = 1;

  final SecretStore _store;
  // An explicit count is a test seam; production chooses by KDF availability.
  final int? _iterations;

  AppLockConfig _config;
  PinHash? _pin;
  PinHash? _verifiedForSettlement;

  @override
  AppLockConfig get config => _config;

  /// Reads the stored record.
  ///
  /// A record that cannot be read leaves the lock off instead of failing the
  /// start: the fallback fits a lock, since the content behind it is only
  /// reachable while the lock is on. A record that cannot be parsed is treated
  /// as no lock as well, but writes still work so a new PIN can replace it.
  ///
  /// The read is retried before that fallback is accepted. The system
  /// keystore can refuse a read in the first moments after a cold boot and
  /// answer again a beat later, and failing open on the first refusal would
  /// hand an unlocked session to whoever picked the phone up.
  static Future<AppLockRepo> open({
    SecretStore store = const FlutterSecretStore(),
    int? iterations,
    List<Duration> readBackoff = _readBackoff,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final raw = await store.read(storageKey);
        return _parse(store, raw, iterations);
      } catch (e, stack) {
        if (attempt >= readBackoff.length) {
          mainLog.e('App lock: secure storage is unavailable', e, stack);
          return const DisabledAppLockRepo();
        }
        mainLog.w('App lock: the secure storage read failed, retrying', e);
        await Future<void>.delayed(readBackoff[attempt]);
      }
    }
  }

  static const List<Duration> _readBackoff = [
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
  ];

  static AppLockRepo _parse(SecretStore store, String? raw, int? iterations) {
    if (raw == null || raw.isEmpty) {
      return SecureAppLockRepo._(
        store,
        const AppLockConfig(),
        null,
        iterations,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }

    if (decoded is! Map) {
      mainLog.w('App lock: the stored record is not readable, ignoring it');
      return SecureAppLockRepo._(
        store,
        const AppLockConfig(),
        null,
        iterations,
      );
    }

    if (decoded['schema'] != schema) {
      mainLog.w(
        'App lock: unknown record schema ${decoded['schema']}, ignoring it',
      );
      return SecureAppLockRepo._(
        store,
        const AppLockConfig(),
        null,
        iterations,
      );
    }

    // The entry never wrote a length before this field existed, and a
    // damaged one cannot be trusted: both read as unknown rather than a
    // guess. The gate falls back to a manual submit for such a record, and
    // the next correct entry heals the field from the PIN that opened it.
    final length = decoded['pinLength'];
    // Failures recorded before the field existed read as a fresh counter.
    final attempts = decoded['failedAttempts'];
    final retryAt = decoded['retryAt'];
    final pin = PinHash.tryParse(decoded['pin']);
    // A missing verifier cannot lock anything, so the record is reported as
    // unlocked even if it was written as enabled.
    final enabled = decoded['enabled'] == true && pin != null;
    return SecureAppLockRepo._(
      store,
      AppLockConfig(
        enabled: enabled,
        hasPin: pin != null,
        timeout: LockTimeout.fromName(decoded['timeout']),
        pinLength:
            length is int && length >= minPinLength && length <= maxPinLength
            ? length
            : null,
        failedAttempts: attempts is int && attempts > 0 ? attempts : 0,
        retryAt: retryAt is String ? DateTime.tryParse(retryAt) : null,
      ),
      pin,
      iterations,
    );
  }

  @override
  Future<void> enable(String pin) async {
    final hashed = await _hash(pin);
    // A new PIN starts with a clean failure record, so an old run of guesses
    // does not outlive the entry it was aimed at.
    final next = AppLockConfig(
      enabled: true,
      hasPin: true,
      timeout: _config.timeout,
      pinLength: pin.length,
    );
    await _persist(next, hashed);
  }

  @override
  Future<void> changePin(String pin) async {
    final hashed = await _hash(pin);
    final next = AppLockConfig(
      enabled: _config.enabled,
      hasPin: true,
      timeout: _config.timeout,
      pinLength: pin.length,
    );
    await _persist(next, hashed);
  }

  @override
  Future<void> disable() async {
    try {
      await _store.delete(storageKey);
    } catch (e, stack) {
      mainLog.e('App lock: failed to remove the record', e, stack);
      throw const AppLockUnavailableException();
    }

    _pin = null;
    _config = _config.copyWith(enabled: false, hasPin: false);
  }

  @override
  Future<bool> verify(String pin) async {
    final stored = _pin;
    if (stored == null) return false;

    final ok = await _matches(stored, pin);
    // A queued change-PIN may finish while verification runs. Its verifier
    // must not be replaced later by housekeeping for the previous PIN.
    if (ok && identical(_pin, stored)) _verifiedForSettlement = stored;
    return ok;
  }

  /// Checks [pin] against [stored] without touching the live record.
  ///
  /// The native provider keeps the derivation off the UI isolate; a device
  /// without it, or a PIN it cannot take, falls back to the portable path.
  Future<bool> _matches(PinHash stored, String pin) async {
    final native = await NativePinKdf.derive(
      pin,
      stored.salt,
      stored.iterations,
    );
    if (native != null) return constantTimeEquals(stored.hash, native);
    return Isolate.run(() => stored.matches(pin));
  }

  @override
  Future<void> setTimeout(LockTimeout timeout) async {
    if (timeout == _config.timeout) return;
    await _persist(config.copyWith(timeout: timeout), _pin);
  }

  @override
  Future<DateTime?> recordFailure(DateTime now) async {
    final attempts = _config.failedAttempts + 1;
    final retryAt = pinRetryAt(attempts, now);
    final next = AppLockConfig(
      enabled: _config.enabled,
      hasPin: _config.hasPin,
      timeout: _config.timeout,
      pinLength: _config.pinLength,
      failedAttempts: attempts,
      retryAt: retryAt,
    );
    await _adopt(next, _pin);
    return retryAt;
  }

  @override
  Future<void> clearFailures() async {
    if (_config.failedAttempts == 0 && _config.retryAt == null) return;
    final next = AppLockConfig(
      enabled: _config.enabled,
      hasPin: _config.hasPin,
      timeout: _config.timeout,
      pinLength: _config.pinLength,
    );
    await _adopt(next, _pin);
  }

  @override
  Future<void> settleAfterUnlock(String pin) async {
    final stored = _verifiedForSettlement;
    _verifiedForSettlement = null;
    if (stored == null || !identical(_pin, stored)) return;

    // Housekeeping rewrites the verifier, so the PIN it derives must be the
    // one that opened it. A stale marker or a wrong argument must never turn
    // the stored verifier into a hash of another PIN.
    if (!await _matches(stored, pin)) return;
    if (!identical(_pin, stored)) return;

    PinHash? upgraded;
    final target = _iterations ?? nativePinIterations;
    if (stored.iterations < target) {
      final salt = PinHash.randomSalt();
      final bytes = await NativePinKdf.derive(pin, salt, target);
      if (bytes != null) {
        upgraded = PinHash(salt: salt, hash: bytes, iterations: target);
      }
    }
    if (!identical(_pin, stored)) return;

    final length = _config.pinLength ?? pin.length;
    final dirty =
        upgraded != null ||
        _config.failedAttempts != 0 ||
        _config.retryAt != null ||
        _config.pinLength != length;
    if (!dirty) return;

    final next = AppLockConfig(
      enabled: _config.enabled,
      hasPin: _config.hasPin,
      timeout: _config.timeout,
      pinLength: length,
    );
    // The upgrade keeps the same PIN. A failed write can therefore retain it
    // in memory without making the stored PIN and the live PIN disagree.
    await _adopt(next, upgraded ?? stored);
  }

  /// Native work runs on Android's task queue; the portable fallback runs in
  /// an isolate. Neither path computes PBKDF2 on the Flutter UI isolate.
  Future<PinHash> _hash(String pin) async {
    try {
      final salt = PinHash.randomSalt();
      final nativeIterations = _iterations ?? nativePinIterations;
      final bytes = await NativePinKdf.derive(pin, salt, nativeIterations);
      if (bytes != null) {
        return PinHash(salt: salt, hash: bytes, iterations: nativeIterations);
      }
      final iterations = _iterations ?? defaultPinIterations;
      return await Isolate.run(
        () => PinHash.create(pin, iterations: iterations),
      );
    } catch (e, stack) {
      // The isolate itself failed — a refused spawn, memory pressure. The
      // setup sheet only knows AppLockUnavailableException; an escaping
      // error would leave it spinning with no way out.
      mainLog.e('App lock: the PIN could not be hashed', e, stack);
      throw const AppLockUnavailableException();
    }
  }

  /// Like [_persist], but a failed write still adopts the record in memory.
  ///
  /// The attempt ledger uses it: a guess must cost the same whether or not
  /// storage answers, and the next successful write carries the count along.
  /// The PIN-changing writes keep [_persist]'s all-or-nothing rule instead —
  /// a half-saved PIN would lock the user out of their own app.
  Future<void> _adopt(AppLockConfig next, PinHash? pin) async {
    try {
      await _persist(next, pin);
    } on AppLockUnavailableException {
      _pin = pin;
      _config = next;
    }
  }

  /// Writes the record first and only then adopts it, so a failed write leaves
  /// both the stored and the in-memory state on the previous PIN.
  Future<void> _persist(AppLockConfig next, PinHash? pin) async {
    final record = jsonEncode({
      'schema': schema,
      'enabled': next.enabled,
      'timeout': next.timeout.name,
      'pinLength': next.pinLength,
      'failedAttempts': next.failedAttempts,
      if (next.retryAt case final at?) 'retryAt': at.toIso8601String(),
      'pin': pin?.toJson(),
    });

    try {
      await _store.write(storageKey, record);
    } catch (e, stack) {
      mainLog.e('App lock: failed to store the record', e, stack);
      throw const AppLockUnavailableException();
    }

    _pin = pin;
    _config = next;
  }
}

/// Stand-in used when secure storage could not be read at boot.
///
/// The lock starts off, and every attempt to turn it on reports that the
/// secret store is unavailable instead of pretending the PIN was saved.
class DisabledAppLockRepo implements AppLockRepo {
  const DisabledAppLockRepo();

  @override
  AppLockConfig get config => const AppLockConfig();

  @override
  Future<void> enable(String pin) async {
    throw const AppLockUnavailableException();
  }

  @override
  Future<void> changePin(String pin) async {
    throw const AppLockUnavailableException();
  }

  @override
  Future<void> disable() async {}

  @override
  Future<bool> verify(String pin) async => false;

  @override
  Future<void> setTimeout(LockTimeout timeout) async {}

  @override
  Future<DateTime?> recordFailure(DateTime now) async => null;

  @override
  Future<void> clearFailures() async {}

  @override
  Future<void> settleAfterUnlock(String pin) async {}
}
