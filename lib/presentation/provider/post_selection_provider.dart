import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final postSelectionProvider = NotifierProvider<PostSelectionNotifier, Set<int>>(
  PostSelectionNotifier.new,
);

class PostSelectionNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => {};

  void toggle(int postId) {
    if (state.contains(postId)) {
      state = {...state}..remove(postId);
    } else {
      state = {...state, postId};
    }
  }

  void select(int postId) {
    state = {...state, postId};
  }

  void deselect(int postId) {
    state = {...state}..remove(postId);
  }

  void selectAll(List<Post> posts) {
    state = posts.map((p) => p.id).toSet();
  }

  /// Drops every selected id that is not in [ids].
  ///
  /// The selection only names posts the reader can still act on: a post a
  /// local filter, a newly blocked tag or a reload took off the grid cannot be
  /// downloaded or favorited from the bar any more, and counting it would make
  /// the bar lie about what the action will touch. Emits nothing when every
  /// selected id survives, so it can run on every filter change.
  void retainAll(Set<int> ids) {
    if (state.every(ids.contains)) return;
    state = state.where(ids.contains).toSet();
  }

  void clear() {
    state = {};
  }

  bool isSelected(int postId) => state.contains(postId);

  int get count => state.length;

  bool get hasSelection => state.isNotEmpty;
}
