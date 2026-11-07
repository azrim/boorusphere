import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';

abstract interface class SearchHistoryRepo {
  Map<int, SearchHistory> get all;
  Future<void> save(String value, String serverId);
  Future<void> delete(key);

  /// Puts [entry] back under its original [key], count included. Used by the
  /// undo of a dismissed history row, which has to restore the entry as it
  /// was instead of counting a new search.
  Future<void> restore(int key, SearchHistory entry);

  Future<void> clear();

  /// Restores [src] and reports how many queries it carried, or null when the
  /// payload is not a history list. An empty list is zero: the archive named an
  /// empty store, and the stored history is emptied to match.
  Future<int?> import(String src);
  Future<BackupItem> export();
}
