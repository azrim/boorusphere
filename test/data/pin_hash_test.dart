import 'package:boorusphere/data/repository/app_lock/pin_hash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinHash', () {
    test('accepts the PIN it was made from and rejects another', () {
      final hash = PinHash.create('1234', iterations: 10);

      expect(hash.matches('1234'), isTrue);
      expect(hash.matches('1235'), isFalse);
      expect(hash.matches('12345'), isFalse);
      expect(hash.matches(''), isFalse);
    });

    test('salts every record, so one PIN never yields one hash', () {
      final first = PinHash.create('1234', iterations: 10);
      final second = PinHash.create('1234', iterations: 10);

      expect(first.salt, isNot(second.salt));
      expect(first.hash, isNot(second.hash));
      expect(first.iterations, 10);
    });

    test('a fresh salt is long enough and never repeats', () {
      final first = PinHash.randomSalt();
      final second = PinHash.randomSalt();

      expect(first, hasLength(16));
      expect(first, isNot(second));
    });

    test('round-trips through its stored form', () {
      final original = PinHash.create('987654', iterations: 10);
      final parsed = PinHash.tryParse(original.toJson());

      expect(parsed, isNotNull);
      expect(parsed!.matches('987654'), isTrue);
      expect(parsed.iterations, 10);
    });

    test('rejects a malformed record instead of throwing', () {
      expect(PinHash.tryParse(null), isNull);
      expect(PinHash.tryParse('nope'), isNull);
      expect(PinHash.tryParse(const <String, Object>{}), isNull);
      expect(
        PinHash.tryParse(const {
          'iterations': 0,
          'salt': 'AA==',
          'hash': 'AA==',
        }),
        isNull,
      );
      expect(
        PinHash.tryParse(const {'iterations': 10, 'salt': '', 'hash': 'AA=='}),
        isNull,
      );
      expect(
        PinHash.tryParse(const {
          'iterations': 10,
          'salt': 'not base64!',
          'hash': 'AA==',
        }),
        isNull,
      );
    });

    test('compares without exiting at the first different byte', () {
      expect(constantTimeEquals(const [1, 2, 3], const [1, 2, 3]), isTrue);
      expect(constantTimeEquals(const [1, 2, 3], const [1, 2, 4]), isFalse);
      expect(constantTimeEquals(const [1, 2], const [1, 2, 3]), isFalse);
    });
  });
}
