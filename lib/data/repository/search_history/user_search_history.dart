import 'dart:convert';

import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/domain/repository/search_history_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:hive_ce/hive.dart';

class UserSearchHistoryRepo implements SearchHistoryRepo {
  UserSearchHistoryRepo(this.box);
  final Box<SearchHistory> box;

  @override
  Map<int, SearchHistory> get all => Map.from(box.toMap());

  @override
  Future<void> save(String value, String serverId) async {
    final query = value.trim();
    if (query.isEmpty) return;

    // Dedup + reorder-on-reuse: if the query already exists in
    // history (regardless of server), delete the prior occurrence(s)
    // first so the new entry rises to the top when the UI iterates
    // newest-first. Hive auto-incrementing keys guarantee the most
    // recently `add()`-ed entry has the highest key. The previous count is
    // carried over and bumped, so the row keeps how often the query was used.
    final existingKeys = <int>[];
    var count = 0;
    for (final entry in box.toMap().entries) {
      if (entry.value.query == query && entry.key is int) {
        existingKeys.add(entry.key as int);
        if (entry.value.count > count) count = entry.value.count;
      }
    }
    if (existingKeys.isNotEmpty) {
      await box.deleteAll(existingKeys);
    }
    await box.add(
      SearchHistory(query: query, server: serverId, count: count + 1),
    );
  }

  @override
  Future<void> delete(key) => box.delete(key);

  @override
  Future<void> clear() => box.clear();

  @override
  Future<int?> import(String src) async {
    final List maps;
    try {
      maps = jsonDecode(src) as List;
    } catch (e) {
      // Not a history list this build can read; keep the stored history.
      return null;
    }

    // An empty list is the archive saying nothing was searched for. The stored
    // history is emptied to match instead of surviving as a stale copy.
    if (maps.isEmpty) {
      await box.clear();
      return 0;
    }

    // Every entry is decoded before the box is touched, so a malformed entry
    // reaches the caller with the stored history still intact. Keys are
    // assigned here rather than by `add()` so the restored order is the one
    // the backup was written in.
    final restored = <int, SearchHistory>{};
    for (final map in maps) {
      if (map is! Map) continue;
      restored[restored.length] = SearchHistory.fromJson(Map.from(map));
    }
    // A list with nothing usable in it is not an empty list: it leaves the
    // stored history alone.
    if (restored.isEmpty) return null;

    await box.putAll(restored);
    final stale = box.keys.where((it) => !restored.containsKey(it)).toList();
    if (stale.isNotEmpty) await box.deleteAll(stale);
    return restored.length;
  }

  @override
  Future<BackupItem> export() async {
    return BackupItem(key, box.values.map((e) => e.toJson()).toList());
  }

  static const String key = 'searchHistory';
  static Future<void> prepare() => Hive.openBox<SearchHistory>(key);
}
