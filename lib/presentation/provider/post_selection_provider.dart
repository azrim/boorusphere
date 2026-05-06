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

  void clear() {
    state = {};
  }

  bool isSelected(int postId) => state.contains(postId);

  int get count => state.length;

  bool get hasSelection => state.isNotEmpty;
}
