import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favorite_post_state.g.dart';

// Favorites mirror the repo, and every screen reads them: the drawer badge,
// the Favorites page, the timeline menu. A batch write awaits between saves, so
// an auto-disposed provider would be gone before the second one landed.
@Riverpod(keepAlive: true)
class FavoritePostState extends _$FavoritePostState {
  /// Read once: an undo kept by the root messenger can still run after the
  /// page that started it is gone, and a backup import can invalidate this
  /// provider while that action waits. The repo outlives both, so the write can
  /// still land; only the state publication has to check that this element is
  /// still alive.
  late final _repo = ref.read(favoritePostRepoProvider);

  @override
  Iterable<Post> build() => _repo.get();

  /// Whether [post] is saved, matched by the same identity the storage key
  /// uses: a post id is only unique within a booru, so the server counts too.
  bool isFavorite(Post post) =>
      state.any((it) => it.id == post.id && it.serverId == post.serverId);

  Future<void> clear() async {
    await _repo.clear();
    if (!ref.mounted) return;
    state = _repo.get();
  }

  Future<void> remove(Post post) async {
    await _repo.remove(post);
    if (!ref.mounted) return;
    state = _repo.get();
  }

  /// Saves [post], replacing an earlier snapshot of the same post so refreshed
  /// metadata such as score or tags is kept.
  Future<void> save(Post post) async {
    await _repo.save(post);
    if (!ref.mounted) return;
    state = _repo.get();
  }
}
