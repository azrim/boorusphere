import 'dart:convert';

import 'package:boorusphere/data/encryption.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/repository/settings_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/entity/download_quality.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:hive_ce/hive.dart';

class UserSettingsRepo implements SettingsRepo {
  UserSettingsRepo(this.box);

  /// Box that persists the settings, or null when boot could not open it.
  ///
  /// A missing box only costs persistence: reads answer with the caller's
  /// default and writes are held for the session, so the app keeps running and
  /// the failure is reported instead of taking the UI down.
  final Box? box;

  /// Values written while [box] is unavailable or a write failed, so a choice
  /// made in this session is still the one that reads back.
  final Map<String, Object?> _memory = {};

  @override
  bool get isPersistent => box != null;

  @override
  T get<T>(Setting key, {required T or}) {
    final value = _memory[key.name] ?? box?.get(key.name);
    return value == null ? or : value as T;
  }

  @override
  Future<void> put<T>(Setting key, T value) async {
    await _write(key.name, value);
  }

  @override
  Future<void> import(String src) async {
    final Map map = jsonDecode(src);
    if (map.isEmpty) return;

    // The new values are stored before the keys the backup does not mention
    // are dropped: deleting first left the user without any setting when a
    // write failed halfway through.
    var stored = true;
    for (final entry in map.entries) {
      stored &= await _write('${entry.key}', _decode(entry.key, entry.value));
    }
    if (!stored) return;

    final target = box;
    if (target == null) return;
    final stale = target.keys.where((it) => !map.containsKey(it)).toList();
    if (stale.isNotEmpty) await target.deleteAll(stale);
  }

  @override
  Future<BackupItem> export() async {
    final data = box?.toMap() ?? const <dynamic, dynamic>{};
    return BackupItem(
      key,
      data.map((key, value) {
        if (value is DownloadQuality) {
          return MapEntry(key, value.name);
        } else if (value is BooruRating) {
          return MapEntry(key, value.name);
        } else {
          return MapEntry(key, value);
        }
      }),
    );
  }

  /// Stores [value] under [key] and reports whether it reached the disk.
  Future<bool> _write(String key, Object? value) async {
    _memory[key] = value;
    final target = box;
    if (target == null) return true;

    try {
      await target.put(key, value);
      _memory.remove(key);
      return true;
    } catch (e, stack) {
      mainLog.e('Settings: failed to store "$key"', e, stack);
      return false;
    }
  }

  /// Maps a backup entry to the type the box stores for [key].
  static Object? _decode(Object? key, Object? value) {
    if (key == Setting.downloadsQuality.name) {
      return DownloadQuality.fromName('$value');
    } else if (key == Setting.searchRating.name) {
      return BooruRating.fromName('$value');
    }
    return value;
  }

  static const String key = 'settings';

  /// Box holding a copy of the plain entries while they are rewritten as
  /// encrypted ones. One that survives a start means that migration stopped
  /// before the encrypted box was complete.
  static const String _backupKey = 'settings_migration_backup';

  /// Set once a missing box has been logged, so a screen that reads ten
  /// settings does not report the same failure ten times.
  static bool _reportedUnavailable = false;

  /// The open settings box, or null when boot could not open it.
  static Box? openBox() {
    if (Hive.isBoxOpen(key)) return Hive.box(key);
    if (!_reportedUnavailable) {
      _reportedUnavailable = true;
      mainLog.e('Settings: the box is not open, using defaults for this run');
    }
    return null;
  }

  static Future<void> prepare() async {
    final cipher = await EncryptionHelper.getCipher();
    await _recoverInterruptedMigration(cipher);

    Object? openError;
    try {
      await Hive.openBox(key, encryptionCipher: cipher);
      return;
    } catch (e) {
      // Migration: old data was unencrypted
      openError = e;
    }

    final data = await _readUnencrypted();
    if (data == null) {
      // The box is on disk but neither the key nor a plain read opens it: the
      // entries cannot be recovered, so they are left untouched instead of
      // being replaced by an empty box.
      throw openError;
    }

    await _migrateToEncrypted(data, cipher);
  }

  /// Reads the box without a cipher, or returns null when its entries are
  /// encrypted.
  static Future<Map<dynamic, dynamic>?> _readUnencrypted() async {
    try {
      final plain = await Hive.openBox(key);
      final data = plain.toMap();
      await plain.close();
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Rewrites the plain box as an encrypted one.
  ///
  /// The plain entries are copied to an encrypted backup first: they are the
  /// only copy of the user's settings, so a failure between dropping the box
  /// and writing the encrypted one would otherwise lose all of them.
  static Future<void> _migrateToEncrypted(
    Map<dynamic, dynamic> data,
    HiveAesCipher cipher,
  ) async {
    final backup = await Hive.openBox(_backupKey, encryptionCipher: cipher);
    await backup.putAll(data);
    await backup.flush();
    await backup.close();

    await Hive.deleteBoxFromDisk(key);

    final encrypted = await Hive.openBox(key, encryptionCipher: cipher);
    await encrypted.putAll(data);
    await encrypted.flush();

    await Hive.deleteBoxFromDisk(_backupKey);
  }

  /// Writes back the copy left by an interrupted migration, then drops it.
  ///
  /// Runs before the box is opened, so a start that follows a half-finished
  /// migration finds its settings instead of an empty box.
  static Future<void> _recoverInterruptedMigration(HiveAesCipher cipher) async {
    if (!await Hive.boxExists(_backupKey)) return;

    final backup = await Hive.openBox(_backupKey, encryptionCipher: cipher);
    final data = backup.toMap();
    await backup.close();

    if (data.isEmpty) {
      await Hive.deleteBoxFromDisk(_backupKey);
      return;
    }

    final restored = await _openForRestore(cipher);
    await restored.putAll(data);
    await restored.flush();

    await Hive.deleteBoxFromDisk(_backupKey);
  }

  /// The settings box, opened with the cipher when it is encrypted and plainly
  /// when it is still the legacy one.
  static Future<Box> _openForRestore(HiveAesCipher cipher) async {
    try {
      return await Hive.openBox(key, encryptionCipher: cipher);
    } catch (_) {
      return Hive.openBox(key);
    }
  }
}
