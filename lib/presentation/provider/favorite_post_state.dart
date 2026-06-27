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

  Set<int> get _favoriteIds => state.map((p) => p.id).toSet();

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

  Future<void> save(Post post) async {
    if (_favoriteIds.contains(post.id)) return;

    final repo = ref.read(favoritePostRepoProvider);
    await repo.save(post);
    state = repo.get();
  }
}
