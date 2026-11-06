import 'dart:convert';

import 'package:boorusphere/data/repository/app_lock/secret_store.dart';
import 'package:boorusphere/data/repository/app_lock/secure_app_lock_repo.dart';
import 'package:boorusphere/domain/repository/app_lock_repo.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecretStore implements SecretStore {
  final Map<String, String> values = {};
  bool readThrows = false;
  bool writeThrows = false;
  bool deleteThrows = false;

  @override
  Future<String?> read(String key) async {
    if (readThrows) throw Exception('read failed');
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
  late _FakeSecretStore store;

  setUp(() {
    store = _FakeSecretStore();
  });

  Future<AppLockRepo> open() {
    return SecureAppLockRepo.open(store: store, iterations: 10);
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

  test('a record without a length reads as the longest PIN', () async {
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
    expect(repo.config.pinLength, maxPinLength);
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
