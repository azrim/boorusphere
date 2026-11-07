import 'dart:convert';

import 'package:boorusphere/data/repository/app_lock/native_pin_kdf.dart';
import 'package:boorusphere/data/repository/app_lock/pin_hash.dart';

import 'package:boorusphere/data/repository/app_lock/secret_store.dart';
import 'package:boorusphere/data/repository/app_lock/secure_app_lock_repo.dart';
import 'package:boorusphere/domain/repository/app_lock_repo.dart';
import 'package:boorusphere/presentation/provider/app_lock/lockout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecretStore implements SecretStore {
  final Map<String, String> values = {};
  bool readThrows = false;
  bool writeThrows = false;
  bool deleteThrows = false;

  /// How many reads fail before the store answers again, like a keystore
  /// that is not ready in the first moments after a cold boot.
  int readFailures = 0;

  @override
  Future<String?> read(String key) async {
    if (readThrows) throw Exception('read failed');
    if (readFailures > 0) {
      readFailures--;
      throw Exception('read failed');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (writeThrows) throw Exception('write failed');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (deleteThrows) throw Exception('delete failed');
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeSecretStore store;

  tearDown(
    () => messenger.setMockMethodCallHandler(NativePinKdf.channel, null),
  );

  setUp(() {
    store = _FakeSecretStore();
  });

  Future<AppLockRepo> open({List<Duration>? readBackoff}) {
    return SecureAppLockRepo.open(
      store: store,
      iterations: 10,
      readBackoff: readBackoff ?? const [Duration.zero, Duration.zero],
    );
  }

  test('starts off when nothing was stored', () async {
    final repo = await open();

    expect(repo.config.enabled, isFalse);
    expect(repo.config.hasPin, isFalse);
    expect(repo.config.isActive, isFalse);
    expect(repo.config.timeout, LockTimeout.immediate);
    expect(await repo.verify('1234'), isFalse);
    expect(store.values, isEmpty);
  });

  test('enable stores a verifier, and verify matches only the PIN', () async {
    final repo = await open();
    await repo.enable('1234');

    expect(repo.config.enabled, isTrue);
    expect(repo.config.hasPin, isTrue);
    expect(repo.config.isActive, isTrue);
    expect(repo.config.pinLength, 4);
    expect(await repo.verify('1234'), isTrue);
    expect(await repo.verify('1235'), isFalse);

    final raw = store.values[SecureAppLockRepo.storageKey]!;
    final record = jsonDecode(raw) as Map<String, dynamic>;
    expect(record['schema'], 1);
    expect(record['enabled'], isTrue);
    expect(record['timeout'], 'immediate');
    expect(record['pinLength'], 4);
    expect(record['pin'], isA<Map>());
    expect(raw, isNot(contains('1234')));
  });

  test('a stored record keeps its state across a restart', () async {
    final first = await open();
    await first.enable('4321');
    await first.setTimeout(LockTimeout.minutes1);

    final reopened = await open();
    expect(reopened.config.enabled, isTrue);
    expect(reopened.config.hasPin, isTrue);
    expect(reopened.config.timeout, LockTimeout.minutes1);
    expect(reopened.config.pinLength, 4);
    expect(await reopened.verify('4321'), isTrue);
  });

  test(
    'changing the PIN replaces the verifier and keeps the lock on',
    () async {
      final repo = await open();
      await repo.enable('1111');
      await repo.changePin('22222');

      expect(repo.config.enabled, isTrue);
      expect(repo.config.pinLength, 5);
      expect(await repo.verify('1111'), isFalse);
      expect(await repo.verify('22222'), isTrue);
    },
  );

  test('disable drops the record and the verifier', () async {
    final repo = await open();
    await repo.enable('1234');
    await repo.disable();

    expect(repo.config.enabled, isFalse);
    expect(repo.config.hasPin, isFalse);
    expect(store.values, isEmpty);
    expect(await repo.verify('1234'), isFalse);
  });

  test('a corrupt record leaves the lock off and can be replaced', () async {
    store.values[SecureAppLockRepo.storageKey] = '{';

    final repo = await open();
    expect(repo.config.isActive, isFalse);

    await repo.enable('1234');
    expect(repo.config.isActive, isTrue);
    expect(await repo.verify('1234'), isTrue);
  });

  test('an unknown schema is ignored instead of guessed', () async {
    store.values[SecureAppLockRepo.storageKey] = jsonEncode({
      'schema': 99,
      'enabled': true,
      'timeout': 'minutes5',
      'pinLength': 4,
      'pin': {
        'iterations': 10,
        'salt': base64Encode(const [1, 2, 3]),
        'hash': base64Encode(const [4, 5, 6]),
      },
    });

    final repo = await open();
    expect(repo.config.isActive, isFalse);
  });

  test('enabled without a verifier is reported as off', () async {
    store.values[SecureAppLockRepo.storageKey] = jsonEncode({
      'schema': 1,
      'enabled': true,
      'timeout': 'immediate',
      'pinLength': 4,
      'pin': null,
    });

    final repo = await open();
    expect(repo.config.enabled, isFalse);
    expect(repo.config.hasPin, isFalse);
    expect(await repo.verify('1234'), isFalse);
  });

  test('a record without a length reads as unknown', () async {
    store.values[SecureAppLockRepo.storageKey] = jsonEncode({
      'schema': 1,
      'enabled': true,
      'timeout': 'immediate',
      'pin': {
        'iterations': 10,
        'salt': base64Encode(const [1, 2, 3]),
        'hash': base64Encode(const [4, 5, 6]),
      },
    });

    final repo = await open();
    // Guessing the longest length would auto-submit a shorter PIN as a
    // wrong one; unknown lets the gate submit by hand instead.
    expect(repo.config.pinLength, isNull);
  });

  test('an impossible length reads as unknown too', () async {
    final repo = await open();
    await repo.enable('1234');

    final record =
        jsonDecode(store.values[SecureAppLockRepo.storageKey]!)
            as Map<String, dynamic>;
    record['pinLength'] = 99;
    store.values[SecureAppLockRepo.storageKey] = jsonEncode(record);

    final reopened = await open();
    expect(reopened.config.pinLength, isNull);
  });

  test('settling after unlock heals a missing length', () async {
    final repo = await open();
    await repo.enable('1234');
    await repo.recordFailure(DateTime(2026, 1, 1));

    // Rewrite the record the way an old build left it: no length.
    final record =
        jsonDecode(store.values[SecureAppLockRepo.storageKey]!)
            as Map<String, dynamic>;
    record.remove('pinLength');
    store.values[SecureAppLockRepo.storageKey] = jsonEncode(record);

    final legacy = await open();
    expect(legacy.config.pinLength, isNull);
    expect(legacy.config.failedAttempts, 1);

    expect(await legacy.verify('1234'), isTrue);
    await legacy.settleAfterUnlock('1234');
    expect(legacy.config.pinLength, 4);
    expect(legacy.config.failedAttempts, 0);

    final healed = await open();
    expect(healed.config.pinLength, 4);
  });

  test('a settle with nothing to heal leaves the record alone', () async {
    final repo = await open();
    await repo.enable('1234');
    final raw = store.values[SecureAppLockRepo.storageKey];

    expect(await repo.verify('1234'), isTrue);
    await repo.settleAfterUnlock('1234');
    expect(store.values[SecureAppLockRepo.storageKey], raw);
  });

  test('a settle queued behind a PIN change leaves the new PIN', () async {
    final repo = await open();
    await repo.enable('1234');
    await repo.recordFailure(DateTime(2026, 1, 1));

    expect(await repo.verify('1234'), isTrue);
    await repo.changePin('5678');
    await repo.settleAfterUnlock('1234');

    expect(await repo.verify('5678'), isTrue);
    expect(await repo.verify('1234'), isFalse);
  });

  group('the native KDF', () {
    late List<Map<Object?, Object?>> calls;

    /// Answers the channel the way the Android side does, so the test can
    /// tell a native derivation apart from the portable fallback.
    void answerNative() {
      calls = [];
      messenger.setMockMethodCallHandler(NativePinKdf.channel, (call) async {
        expect(call.method, 'derive');
        final args = call.arguments as Map<Object?, Object?>;
        calls.add(args);
        return derivePinHash(
          args['pin'] as String,
          args['salt'] as Uint8List,
          args['iterations'] as int,
        );
      });
    }

    test('takes the hashing and the check when the device answers', () async {
      answerNative();
      final repo = await open();
      await repo.enable('1234');
      expect(calls, hasLength(1));
      expect(calls.single['iterations'], 10);

      expect(await repo.verify('1234'), isTrue);
      expect(await repo.verify('1235'), isFalse);
      expect(calls, hasLength(3));
    });

    test('a refused channel keeps the portable derivation working', () async {
      messenger.setMockMethodCallHandler(NativePinKdf.channel, (call) async {
        throw PlatformException(code: 'kdf_failed');
      });

      final repo = await open();
      await repo.enable('1234');
      expect(await repo.verify('1234'), isTrue);
    });

    test('a non-ASCII PIN stays on its UTF-8 derivation', () async {
      answerNative();
      final repo = await open();
      await repo.enable('päss123');

      // Older gates accepted these, and the stored hash is UTF-8 PBKDF2.
      expect(calls, isEmpty);
      expect(await repo.verify('päss123'), isTrue);
      expect(calls, isEmpty);
    });

    test('settling rewrites a legacy verifier at the native factor', () async {
      answerNative();
      final legacy = PinHash.create('1234', iterations: 10);
      store.values[SecureAppLockRepo.storageKey] = jsonEncode({
        'schema': 1,
        'enabled': true,
        'timeout': 'immediate',
        'pinLength': 4,
        'pin': legacy.toJson(),
      });

      // No iteration override: this is the production choice of factors.
      final repo = await SecureAppLockRepo.open(
        store: store,
        readBackoff: const [Duration.zero],
      );
      expect(await repo.verify('1234'), isTrue);
      expect(calls.single['iterations'], 10);

      await repo.settleAfterUnlock('1234');
      // Verify, the re-check that binds the PIN to the verifier, the rehash.
      expect(calls, hasLength(3));
      expect(calls.last['iterations'], nativePinIterations);
      expect(
        calls.last['salt'] as Uint8List,
        isNot(orderedEquals(legacy.salt)),
      );

      final record =
          jsonDecode(store.values[SecureAppLockRepo.storageKey]!)
              as Map<String, dynamic>;
      final pin = record['pin'] as Map<String, dynamic>;
      expect(pin['iterations'], nativePinIterations);
      expect(
        base64Decode(pin['salt'] as String),
        orderedEquals(calls.last['salt'] as Uint8List),
      );

      // The rewritten verifier still opens the same PIN.
      expect(await repo.verify('1234'), isTrue);
    });

    test('a settle with another PIN never rewrites the verifier', () async {
      answerNative();
      final legacy = PinHash.create('1234', iterations: 10);
      store.values[SecureAppLockRepo.storageKey] = jsonEncode({
        'schema': 1,
        'enabled': true,
        'timeout': 'immediate',
        'pinLength': 4,
        'pin': legacy.toJson(),
      });

      final repo = await SecureAppLockRepo.open(
        store: store,
        readBackoff: const [Duration.zero],
      );
      expect(await repo.verify('1234'), isTrue);

      // The marker proves *a* PIN matched, not that this is that PIN. The
      // rehash would otherwise store a hash of the wrong PIN.
      await repo.settleAfterUnlock('9999');

      final record =
          jsonDecode(store.values[SecureAppLockRepo.storageKey]!)
              as Map<String, dynamic>;
      expect((record['pin'] as Map)['iterations'], 10);
      expect(await repo.verify('1234'), isTrue);
      expect(await repo.verify('9999'), isFalse);
    });
  });

  test('unreadable storage falls back to a disabled repo', () async {
    store.readThrows = true;

    final repo = await open();
    expect(repo.config.isActive, isFalse);
    await expectLater(
      repo.enable('1234'),
      throwsA(isA<AppLockUnavailableException>()),
    );
  });

  test('a read that recovers on retry keeps the lock', () async {
    final first = await open();
    await first.enable('1234');

    // The keystore refuses the first two reads and answers on the third,
    // like a cold boot where the store is not ready yet. Failing open on
    // the first refusal would run this session without the lock.
    store.readFailures = 2;
    final reopened = await open();
    expect(reopened.config.isActive, isTrue);
    expect(await reopened.verify('1234'), isTrue);
    expect(store.readFailures, 0);
  });

  test(
    'a read that never recovers still falls back after the retries',
    () async {
      final first = await open();
      await first.enable('1234');

      store.readFailures = 99;
      final reopened = await open();
      expect(reopened.config.isActive, isFalse);
      // Three attempts: the first read plus one per backoff entry.
      expect(store.readFailures, 96);
    },
  );

  test('a failed write changes neither the record nor the state', () async {
    final repo = await open();
    store.writeThrows = true;

    await expectLater(
      repo.enable('1234'),
      throwsA(isA<AppLockUnavailableException>()),
    );
    expect(repo.config.isActive, isFalse);
    expect(await repo.verify('1234'), isFalse);

    store.writeThrows = false;
    await repo.enable('5678');
    expect(repo.config.isActive, isTrue);
  });

  test('a failed delete keeps the lock on', () async {
    final repo = await open();
    await repo.enable('1234');
    store.deleteThrows = true;

    await expectLater(
      repo.disable(),
      throwsA(isA<AppLockUnavailableException>()),
    );
    expect(repo.config.isActive, isTrue);
    expect(await repo.verify('1234'), isTrue);
  });

  test('the timeout is persisted without dropping the PIN', () async {
    final repo = await open();
    await repo.enable('1234');
    await repo.setTimeout(LockTimeout.seconds30);

    expect(repo.config.timeout, LockTimeout.seconds30);
    final reopened = await open();
    expect(reopened.config.timeout, LockTimeout.seconds30);
    expect(await reopened.verify('1234'), isTrue);
  });

  test('failures persist and clear across a restart', () async {
    final repo = await open();
    await repo.enable('1234');

    final now = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < freePinAttempts; i++) {
      expect(await repo.recordFailure(now), isNull);
    }
    expect(repo.config.failedAttempts, freePinAttempts);

    final reopened = await open();
    expect(reopened.config.failedAttempts, freePinAttempts);
    expect(reopened.config.retryAt, isNull);

    // One past the free attempts, the wait appears and survives a restart.
    await reopened.recordFailure(now.add(const Duration(seconds: 2)));
    expect(reopened.config.retryAt, isNotNull);

    final carried = await open();
    expect(carried.config.failedAttempts, freePinAttempts + 1);
    expect(carried.config.retryAt, isNotNull);

    await carried.clearFailures();
    expect(carried.config.failedAttempts, 0);
    expect(carried.config.retryAt, isNull);

    final cleared = await open();
    expect(cleared.config.failedAttempts, 0);
    expect(cleared.config.retryAt, isNull);
  });

  test('enable replaces the failure record', () async {
    final repo = await open();
    await repo.enable('1234');
    await repo.recordFailure(DateTime(2026, 1, 1));

    await repo.enable('5678');
    expect(repo.config.failedAttempts, 0);
    expect(repo.config.retryAt, isNull);
    expect(await repo.verify('5678'), isTrue);
  });

  test('a guess is counted even when the write fails', () async {
    final repo = await open();
    await repo.enable('1234');
    store.writeThrows = true;

    final now = DateTime(2026, 1, 1, 12);
    for (var i = 0; i <= freePinAttempts; i++) {
      await repo.recordFailure(now);
    }
    // A refused write must not make the guess free: the count is adopted
    // in memory and the throttle still applies to this run.
    expect(repo.config.failedAttempts, freePinAttempts + 1);
    expect(repo.config.retryAt, isNotNull);

    // The next write that lands carries the whole count with it.
    store.writeThrows = false;
    await repo.recordFailure(now);
    final reopened = await open();
    expect(reopened.config.failedAttempts, freePinAttempts + 2);
  });

  test('clearing failures degrades to memory when the write fails', () async {
    final repo = await open();
    await repo.enable('1234');
    final now = DateTime(2026, 1, 1, 12);
    for (var i = 0; i <= freePinAttempts; i++) {
      await repo.recordFailure(now);
    }
    expect(repo.config.retryAt, isNotNull);

    store.writeThrows = true;
    await repo.clearFailures();
    expect(repo.config.failedAttempts, 0);
    expect(repo.config.retryAt, isNull);
  });

  test('a disabled fallback refuses to pretend it saved a PIN', () async {
    const repo = DisabledAppLockRepo();

    expect(repo.config.isActive, isFalse);
    await expectLater(
      repo.enable('1234'),
      throwsA(isA<AppLockUnavailableException>()),
    );
    await expectLater(
      repo.changePin('1234'),
      throwsA(isA<AppLockUnavailableException>()),
    );
    expect(await repo.verify('1234'), isFalse);
    await repo.disable();
    await repo.setTimeout(LockTimeout.never);
  });
}
