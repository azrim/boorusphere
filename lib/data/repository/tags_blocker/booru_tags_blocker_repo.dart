import 'dart:convert';

import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/domain/repository/tags_blocker_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:hive_ce/hive.dart';

class BooruTagsBlockerRepo implements TagsBlockerRepo {
  BooruTagsBlockerRepo(this.box);

  final Box<BooruTag> box;

  @override
  Map<int, BooruTag> get() {
    return Map.from(box.toMap());
  }

  @override
  Future<void> delete(key) async {
    await box.delete(key);
  }

  @override
  Future<void> push(BooruTag value) async {
    final tag = value.copyWith(name: value.name.trim());
    if (tag.name.isNotEmpty && !box.values.contains(tag)) {
      await box.add(tag);
    }
  }

  @override
  Future<void> import(String src) async {
    final List maps = jsonDecode(src);
    if (maps.isEmpty) return;

    // Every entry is decoded before the box is touched, so a malformed entry
    // reaches the caller with the stored blocklist still intact. The entries
    // keep the order the backup was written in.
    final tags = <BooruTag>[];
    for (final data in maps) {
      final BooruTag tag;
      if (data is Map) {
        tag = BooruTag.fromJson(Map.from(data));
      } else if (data is String) {
        tag = BooruTag(name: data);
      } else {
        continue;
      }

      final trimmed = tag.copyWith(name: tag.name.trim());
      if (trimmed.name.isEmpty || tags.contains(trimmed)) continue;
      tags.add(trimmed);
    }
    if (tags.isEmpty) return;

    final restored = {
      for (var index = 0; index < tags.length; index++) index: tags[index],
    };
    await box.putAll(restored);
    final stale = box.keys.where((it) => !restored.containsKey(it)).toList();
    if (stale.isNotEmpty) await box.deleteAll(stale);
  }

  @override
  Future<BackupItem> export() async {
    return BackupItem(boxKey, box.values.map((e) => e.toJson()).toList());
  }

  static const String boxKey = 'blockedTags';

  static Future<void> prepare() async {
    final box = await Hive.openBox(boxKey);
    for (final tag in box.toMap().entries) {
      if (tag.value is String) {
        await box.put(tag.key, BooruTag(name: tag.value));
      }
    }
    await box.close();
    await Hive.openBox<BooruTag>(boxKey);
  }
}
