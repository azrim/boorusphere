import 'package:hive_ce/hive.dart';

/// Thrown when the AES key is gone or unusable while a box that was written
/// with it still exists on disk.
///
/// A freshly generated key cannot decrypt that box, so minting one would make
/// the stored data unrecoverable. [EncryptionHelper.getCipher] fails instead of
/// doing that; the caller is expected to surface the problem to the user
/// without deleting anything.
class MissingEncryptionKeyException implements Exception {
  const MissingEncryptionKeyException(this.boxName);

  /// Box that already holds ciphertext the missing key used to decrypt.
  final String boxName;

  @override
  String toString() =>
      'The encryption key is missing or corrupted, but the encrypted box '
      "'$boxName' already exists on disk. Its contents cannot be recovered "
      'without the original key, so no new key was generated.';
}

class EncryptionHelper {
  static const _keyBoxName = '_encryption_key';
  static const _keyField = 'aes_key';

  /// Boxes opened with the cipher returned by [getCipher].
  ///
  /// The migration copies are listed too: one is left behind while a plain
  /// box is rewritten, and it is then the only copy of the entries. Minting a
  /// fresh key because it was not looked at would make that copy unreadable.
  static const encryptedBoxNames = [
    'server',
    'settings',
    'server_migration',
    'settings_migration_backup',
  ];

  /// Tail of the queue that keeps [getCipher] calls from overlapping. Two
  /// concurrent callers would otherwise both see an empty key box, mint
  /// different keys and leave one of the boxes unreadable on the next start.
  static Future<void> _queue = Future<void>.value();

  /// Cipher for [encryptedBoxNames], generating the key only when no existing
  /// box depends on one.
  ///
  /// Throws [MissingEncryptionKeyException] when a box already holds ciphertext
  /// but the key is missing, which means the key was lost rather than that this
  /// is a first run.
  static Future<HiveAesCipher> getCipher() {
    final result = _queue.then((_) => _resolveCipher());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<HiveAesCipher> _resolveCipher() async {
    final keyBox = await Hive.openBox(_keyBoxName);

    final storedKey = _readKey(keyBox);
    if (storedKey != null) return HiveAesCipher(storedKey);

    final lockedBox = await _firstEncryptedBox();
    if (lockedBox != null) throw MissingEncryptionKeyException(lockedBox);

    final newKey = Hive.generateSecureKey();
    await keyBox.put(_keyField, newKey);
    return HiveAesCipher(newKey);
  }

  /// The stored key, or null when it is absent or not a valid AES-256 key.
  static List<int>? _readKey(Box box) {
    final raw = box.get(_keyField);
    if (raw is List && raw.length == 32) return List<int>.from(raw);
    return null;
  }

  /// Name of a box that only the lost key can open, or null when every box on
  /// disk is still readable without a cipher.
  ///
  /// A box written before encryption existed opens as plain data, so a key can
  /// still be generated for it and the legacy plain-to-encrypted migration
  /// keeps its contents.
  static Future<String?> _firstEncryptedBox() async {
    for (final name in encryptedBoxNames) {
      if (!await Hive.boxExists(name)) continue;
      if (Hive.isBoxOpen(name)) continue;
      if (!await _isReadableWithoutCipher(name)) return name;
    }
    return null;
  }

  static Future<bool> _isReadableWithoutCipher(String name) async {
    final Box box;
    try {
      box = await Hive.openBox(name);
    } catch (_) {
      return false;
    }
    await box.close();
    return true;
  }
}
