import 'dart:io';

import 'package:boorusphere/data/encryption.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const keyBoxName = '_encryption_key';
  const keyField = 'aes_key';

  late Directory dir;

  Future<void> dropStoredKey() async {
    final keyBox = await Hive.openBox(keyBoxName);
    await keyBox.delete(keyField);
    await keyBox.close();
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('boorusphere_encryption_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('EncryptionHelper.getCipher', () {
    test('mints a key when no encrypted box exists yet', () async {
      final cipher = await EncryptionHelper.getCipher();

      expect(await Hive.boxExists('server'), isFalse);

      final keyBox = await Hive.openBox(keyBoxName);
      expect(keyBox.get(keyField), isA<List<dynamic>>());
      expect(keyBox.get(keyField) as List, hasLength(32));

      final box = await Hive.openBox('server', encryptionCipher: cipher);
      await box.put('entry', 'payload');
      await box.close();
    });

    test('refuses to mint a key when an encrypted box is on disk', () async {
      final original = await EncryptionHelper.getCipher();
      final box = await Hive.openBox('server', encryptionCipher: original);
      await box.put('entry', 'payload');
      await box.close();

      await dropStoredKey();

      await expectLater(
        EncryptionHelper.getCipher,
        throwsA(
          isA<MissingEncryptionKeyException>().having(
            (e) => e.boxName,
            'boxName',
            'server',
          ),
        ),
      );

      // The failure mints nothing: the key box stays empty...
      final keyBox = await Hive.openBox(keyBoxName);
      expect(keyBox.containsKey(keyField), isFalse);
      await keyBox.close();

      // ...and the ciphertext is still there for the original key.
      final reopened = await Hive.openBox('server', encryptionCipher: original);
      expect(reopened.get('entry'), 'payload');
      await reopened.close();
    });

    test('mints a key for a box left by a pre-encryption build', () async {
      final legacy = await Hive.openBox('server');
      await legacy.put('entry', 'payload');
      await legacy.close();

      await EncryptionHelper.getCipher();

      final keyBox = await Hive.openBox(keyBoxName);
      expect(keyBox.get(keyField), isA<List<dynamic>>());
      await keyBox.close();

      // The plaintext entries stay in place for the migration to copy.
      final reopened = await Hive.openBox('server');
      expect(reopened.get('entry'), 'payload');
      await reopened.close();
    });

    test('gives concurrent callers the same key', () async {
      final ciphers = await Future.wait([
        EncryptionHelper.getCipher(),
        EncryptionHelper.getCipher(),
      ]);

      expect(ciphers.first.calculateKeyCrc(), ciphers.last.calculateKeyCrc());
    });
  });
}
