import 'dart:convert';
import 'dart:typed_data';

import 'package:boorusphere/presentation/provider/data_backup/backup_cipher.dart';
import 'package:boorusphere/presentation/provider/data_backup/passphrase_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final plaintext = Uint8List.fromList(utf8.encode('PK\x03\x04 a zip, honest'));

  group('preparePassphrase', () {
    test('a confirming field hands over the value without its padding', () {
      expect(preparePassphrase('  hunter22  ', confirm: true), 'hunter22');
    });

    test('the length a field checked is the length that became the key', () {
      // Seven real characters inside eight spaces used to pass a check that
      // measured the padding, then be stored as seven.
      const typed = ' 1234567 ';
      expect(preparePassphrase(typed, confirm: true).length, lessThan(8));
    });

    test('restoring keeps the text exactly as typed', () {
      // An archive written by an older build can carry a passphrase with
      // spaces around it; dropping them here would lock it out for good.
      expect(preparePassphrase('  hunter22  ', confirm: false), '  hunter22  ');
    });
  });

  group('the string that seals is the string that opens', () {
    test('a key is only as good as the exact bytes that made it', () {
      const typed = '  hunter22  ';
      final stored = preparePassphrase(typed, confirm: true);
      final sealed = BackupCipher.encrypt(plaintext, stored);

      expect(BackupCipher.decrypt(sealed, stored), plaintext);
      // Proving the hazard the normalization removes: sealing with one
      // spelling and opening with the padded one is a different key, and the
      // archive reads as damaged rather than as mis-typed.
      expect(
        () => BackupCipher.decrypt(sealed, typed),
        throwsA(isA<BackupCipherException>()),
      );
    });
  });
}
