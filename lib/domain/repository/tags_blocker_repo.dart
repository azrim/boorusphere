import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';

abstract interface class TagsBlockerRepo {
  Map<int, BooruTag> get();
  Future<void> delete(key);
  Future<void> push(BooruTag value);

  /// Restores [src] and reports how many entries it carried, or null when the
  /// payload is not a blocklist. An empty list is zero: the archive named an
  /// empty store, and the stored list is emptied to match.
  Future<int?> import(String src);
  Future<BackupItem> export();
}
