import 'dart:convert';

import 'package:boorusphere/data/encryption.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/repository/settings_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/entity/download_quality.dart';
import 'package:hive_ce/hive.dart';

class UserSettingsRepo implements SettingsRepo {
  UserSettingsRepo(this.box);

  final Box box;

  @override
  T get<T>(Setting key, {required T or}) => box.get(key.name) ?? or;

  @override
  Future<void> put<T>(Setting key, T value) => box.put(key.name, value);

  @override
  Future<void> import(String src) async {
    final Map map = jsonDecode(src);
    if (map.isEmpty) return;
    await box.deleteAll(box.keys);
    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == Setting.downloadsQuality.name) {
        await box.put(key, DownloadQuality.fromName(value));
      } else if (key == Setting.searchRating.name) {
        await box.put(key, BooruRating.fromName(value));
      } else {
        await box.put(key, value);
      }
    }
  }

  @override
  Future<BackupItem> export() async {
    return BackupItem(
      key,
      box.toMap().map((key, value) {
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

  static const String key = 'settings';
  static Future<void> prepare() async {
    final cipher = await EncryptionHelper.getCipher();

    try {
      await Hive.openBox(key, encryptionCipher: cipher);
    } catch (_) {
      // Migration: old data was unencrypted
      final plainBox = await Hive.openBox(key);
      final data = plainBox.toMap();
      await plainBox.close();

      await Hive.deleteBoxFromDisk(key);

      final encryptedBox =
          await Hive.openBox(key, encryptionCipher: cipher);
      await encryptedBox.putAll(data);
      await encryptedBox.flush();
    }
  }
}
