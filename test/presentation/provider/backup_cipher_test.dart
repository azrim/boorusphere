import 'dart:convert';
import 'dart:typed_data';

import 'package:boorusphere/presentation/provider/data_backup/backup_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const passphrase = 'correct horse battery staple';
  final plaintext = Uint8List.fromList(utf8.encode('PK\x03\x04 a zip, honest'));

  group('BackupCipher', () {
    test('roundtrips a plaintext through encrypt and decrypt', () {
      final sealed = BackupCipher.encrypt(plaintext, passphrase);

      expect(BackupCipher.decrypt(sealed, passphrase), plaintext);
    });

    test('rejects a wrong passphrase', () {
      final sealed = BackupCipher.encrypt(plaintext, passphrase);

      expect(
        () => BackupCipher.decrypt(sealed, 'wrong passphrase'),
        throwsA(isA<BackupCipherException>()),
      );
    });

    test('rejects a single flipped byte', () {
      final sealed = BackupCipher.encrypt(plaintext, passphrase);
      // The last byte belongs to the tag, so any edit to the body or the tag
      // has to fail the same way.
      sealed[sealed.length - 1] ^= 0x01;

      expect(
        () => BackupCipher.decrypt(sealed, passphrase),
        throwsA(isA<BackupCipherException>()),
      );
    });

    test('rejects a truncated file', () {
      final sealed = BackupCipher.encrypt(plaintext, passphrase);
      final truncated = Uint8List.sublistView(sealed, 0, sealed.length - 4);

      expect(
        () => BackupCipher.decrypt(truncated, passphrase),
        throwsA(isA<BackupCipherException>()),
      );
    });

    test('tells a plain ZIP apart from an envelope', () {
      final zip = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0]);
      final sealed = BackupCipher.encrypt(plaintext, passphrase);

      expect(BackupCipher.isEncrypted(zip), isFalse);
      expect(BackupCipher.isEncrypted(sealed), isTrue);
    });

    test('adds the header, the salt, the nonce and the tag', () {
      final sealed = BackupCipher.encrypt(plaintext, passphrase);

      // magic (8) + salt (16) + nonce (12) + tag (16)
      expect(sealed.length, plaintext.length + 52);
    });

    test('rejects data that is not an envelope', () {
      final zip = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0]);

      expect(
        () => BackupCipher.decrypt(zip, passphrase),
        throwsA(isA<BackupCipherException>()),
      );
    });
    test('roundtrips through the isolate-backed variants', () async {
      final sealed = await BackupCipher.encryptAsync(plaintext, passphrase);

      expect(await BackupCipher.decryptAsync(sealed, passphrase), plaintext);
    });

    test('rejects a wrong passphrase on the isolate-backed path', () async {
      final sealed = await BackupCipher.encryptAsync(plaintext, passphrase);

      await expectLater(
        BackupCipher.decryptAsync(sealed, 'wrong passphrase'),
        throwsA(isA<BackupCipherException>()),
      );
    });
  });
}
