import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/favorite_post/entity/favorite_post.dart';
import 'package:boorusphere/domain/repository/favorite_post_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:hive_ce/hive.dart';

class UserFavoritePostRepo implements FavoritePostRepo {
  UserFavoritePostRepo(this.box);

  final Box<FavoritePost> box;

  @override
  Iterable<Post> get() {
    return box.values.map((e) => e.post);
  }

  @override
  Future<void> clear() async {
    await box.clear();
  }

  @override
  Future<void> remove(Post post) async {
    final fav = FavoritePost(post: post);
    await box.delete(fav.key);
  }

  @override
  Future<void> save(Post post) async {
    final fav = FavoritePost(
      post: post,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await box.put(fav.key, fav);
  }

  @override
  Future<int?> import(String src) async {
    final List maps;
    try {
      maps = jsonDecode(src) as List;
    } catch (e) {
      // Not a favorites list this build can read; keep the stored favorites.
      return null;
    }

    // An empty list is the archive saying nothing was favorited. The stored
    // list is emptied to match instead of surviving as a stale copy.
    if (maps.isEmpty) {
      await box.clear();
      return 0;
    }

    // Every entry is decoded before the box is touched, so a malformed entry
    // reaches the caller with the stored favorites still intact.
    final restored = <String, FavoritePost>{};
    for (final map in maps) {
      if (map is! Map) continue;
      final fav = FavoritePost.fromJson(Map.from(map));
      restored[fav.key] = fav;
    }
    // A list with nothing usable in it is not an empty list: it leaves the
    // stored favorites alone.
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

  static const String key = 'favorites';
  static Future<void> prepare() => Hive.openBox<FavoritePost>(key);
}
