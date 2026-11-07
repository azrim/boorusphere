import 'dart:convert';

import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/domain/repository/search_history_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:hive_ce/hive.dart';

class UserSearchHistoryRepo implements SearchHistoryRepo {
  UserSearchHistoryRepo(this.box);
  final Box<SearchHistory> box;

  /// Ceiling for the stored history.
  ///
  /// Nothing is ever deleted except a duplicate, so the box used to grow for as
  /// long as the app was used, and every keystroke in the search bar filtered
  /// and sorted the whole thing. Two hundred entries cover what the panel can
  /// ever show and years of ordinary use; the oldest age out first.
  static const int maxEntries = 200;

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
    await _trim();
  }

  /// Drops the oldest entries once the box passes [maxEntries]. Keys grow with
  /// recency (a reuse deletes its old key and adds a higher one), so the
  /// lowest keys are the least recently searched.
  Future<void> _trim() async {
    final overflow = box.length - maxEntries;
    if (overflow <= 0) return;
    final keys = box.keys.cast<int>().toList()..sort();
    await box.deleteAll(keys.take(overflow));
  }

  @override
  Future<void> delete(key) => box.delete(key);

  @override
  Future<void> restore(int key, SearchHistory entry) => box.put(key, entry);

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
    // An archive from an older build can carry more entries than this build
    // keeps, so the same ceiling applies on the way in.
    await _trim();
    return restored.length;
  }

  @override
  Future<BackupItem> export() async {
    return BackupItem(key, box.values.map((e) => e.toJson()).toList());
  }

  static const String key = 'searchHistory';
  static Future<void> prepare() => Hive.openBox<SearchHistory>(key);
}
