import 'package:hive_ce/hive.dart';

class EncryptionHelper {
  static const _keyBoxName = '_encryption_key';
  static const _keyField = 'aes_key';

  static Future<HiveAesCipher> getCipher() async {
    final keyBox = await Hive.openBox(_keyBoxName);

    List<int>? storedKey;
    if (keyBox.containsKey(_keyField)) {
      storedKey = List<int>.from(keyBox.get(_keyField));
    }

    if (storedKey == null || storedKey.length != 32) {
      final newKey = Hive.generateSecureKey();
      await keyBox.put(_keyField, newKey);
      storedKey = newKey;
    }

    return HiveAesCipher(storedKey);
  }
}
