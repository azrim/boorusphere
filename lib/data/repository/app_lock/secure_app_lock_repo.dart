import 'dart:convert';
import 'dart:isolate';

import 'package:boorusphere/data/repository/app_lock/pin_hash.dart';
import 'package:boorusphere/data/repository/app_lock/secret_store.dart';
import 'package:boorusphere/domain/repository/app_lock_repo.dart';
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
  final int _iterations;

  AppLockConfig _config;
  PinHash? _pin;

  @override
  AppLockConfig get config => _config;

  /// Reads the stored record.
  ///
  /// A record that cannot be read leaves the lock off instead of failing the
  /// start: the fallback fits a lock, since the content behind it is only
  /// reachable while the lock is on. A record that cannot be parsed is treated
  /// as no lock as well, but writes still work so a new PIN can replace it.
  static Future<AppLockRepo> open({
    SecretStore store = const FlutterSecretStore(),
    int iterations = defaultPinIterations,
  }) async {
    try {
      final raw = await store.read(storageKey);
      return _parse(store, raw, iterations);
    } catch (e, stack) {
      mainLog.e('App lock: secure storage is unavailable', e, stack);
      return const DisabledAppLockRepo();
    }
  }

  static AppLockRepo _parse(SecretStore store, String? raw, int iterations) {
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
      ),
      pin,
      iterations,
    );
  }

  @override
  Future<void> enable(String pin) async {
    final hashed = await _hash(pin);
    await _persist(config.copyWith(enabled: true, hasPin: true), hashed);
  }

  @override
  Future<void> changePin(String pin) async {
    final hashed = await _hash(pin);
    await _persist(config.copyWith(hasPin: true), hashed);
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

    final value = stored.toJson();
    return Isolate.run(() {
      final parsed = PinHash.tryParse(value);
      return parsed != null && parsed.matches(pin);
    });
  }

  @override
  Future<void> setTimeout(LockTimeout timeout) async {
    if (timeout == _config.timeout) return;
    await _persist(config.copyWith(timeout: timeout), _pin);
  }

  /// Derives the verifier off the main isolate: a PBKDF2 pass here is long
  /// enough to drop frames if it runs while the UI is on screen.
  Future<PinHash> _hash(String pin) async {
    final iterations = _iterations;
    final value = await Isolate.run(() {
      return PinHash.create(pin, iterations: iterations).toJson();
    });
    final hashed = PinHash.tryParse(value);
    if (hashed == null) {
      throw const AppLockUnavailableException();
    }
    return hashed;
  }

  /// Writes the record first and only then adopts it, so a failed write leaves
  /// both the stored and the in-memory state on the previous PIN.
  Future<void> _persist(AppLockConfig next, PinHash? pin) async {
    final record = jsonEncode({
      'schema': schema,
      'enabled': next.enabled,
      'timeout': next.timeout.name,
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
}
