import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';

abstract interface class FavoritePostRepo {
  Iterable<Post> get();
  Future<void> clear();
  Future<void> remove(Post post);
  Future<void> save(Post post);

  /// Restores [src] and reports how many favorites it carried, or null when
  /// the payload is not a favorites list. An empty list is zero: the archive
  /// named an empty store, and the stored list is emptied to match.
  Future<int?> import(String src);
  Future<BackupItem> export();
}
