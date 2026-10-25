import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favorite_post_state.g.dart';

@riverpod
class FavoritePostState extends _$FavoritePostState {
  @override
  Iterable<Post> build() {
    final repo = ref.read(favoritePostRepoProvider);
    return repo.get();
  }

  /// Whether [post] is saved, matched by the same identity the storage key
  /// uses: a post id is only unique within a booru, so the server counts too.
  bool isFavorite(Post post) =>
      state.any((it) => it.id == post.id && it.serverId == post.serverId);

  Future<void> clear() async {
    final repo = ref.read(favoritePostRepoProvider);
    await repo.clear();
    state = repo.get();
  }

  Future<void> remove(Post post) async {
    final repo = ref.read(favoritePostRepoProvider);
    await repo.remove(post);
    state = repo.get();
  }

  /// Saves [post], replacing an earlier snapshot of the same post so refreshed
  /// metadata such as score or tags is kept.
  Future<void> save(Post post) async {
    final repo = ref.read(favoritePostRepoProvider);
    await repo.save(post);
    state = repo.get();
  }
}
