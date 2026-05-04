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
    // recently `add()`-ed entry has the highest key.
    final existingKeys = <int>[];
    for (final entry in box.toMap().entries) {
      if (entry.value.query == query && entry.key is int) {
        existingKeys.add(entry.key as int);
      }
    }
    if (existingKeys.isNotEmpty) {
      await box.deleteAll(existingKeys);
    }
    await box.add(SearchHistory(query: query, server: serverId));
  }

  @override
  Future<void> delete(key) => box.delete(key);

  @override
  Future<void> clear() => box.clear();

  @override
  Future<void> import(String src) async {
    final List maps = jsonDecode(src);
    if (maps.isEmpty) return;
    await box.deleteAll(box.keys);
    for (final map in maps) {
      if (map is Map) {
        final history = SearchHistory.fromJson(Map.from(map));
        await box.add(history);
      }
    }
  }

  @override
  Future<BackupItem> export() async {
    return BackupItem(key, box.values.map((e) => e.toJson()).toList());
  }

  static const String key = 'searchHistory';
  static Future<void> prepare() => Hive.openBox<SearchHistory>(key);
}
