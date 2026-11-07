import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tags_blocker_state.g.dart';

@Riverpod(keepAlive: true)
class TagsBlockerState extends _$TagsBlockerState {
  @override
  Map<int, BooruTag> build() {
    final repo = ref.read(tagsBlockerRepoProvider);
    return repo.get();
  }

  Future<void> delete(key) async {
    final repo = ref.read(tagsBlockerRepoProvider);
    await repo.delete(key);
    state = repo.get();
  }

  Future<void> push({String serverId = '', required String tag}) async {
    final repo = ref.read(tagsBlockerRepoProvider);
    await repo.push(BooruTag(serverId: serverId, name: tag));
    state = repo.get();
  }

  Future<void> pushAll({
    String serverId = '',
    required List<String> tags,
  }) async {
    final repo = ref.read(tagsBlockerRepoProvider);
    for (var tag in tags) {
      await repo.push(BooruTag(serverId: serverId, name: tag));
    }
    state = repo.get();
  }

  /// Removes the entries that [pushAll] would have written for [tags]. Keys
  /// are read from the current state first because the repository addresses
  /// entries by their box key, not by the tag itself.
  Future<void> removeAll({
    String serverId = '',
    required Iterable<String> tags,
  }) async {
    final names = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    if (names.isEmpty) return;

    final repo = ref.read(tagsBlockerRepoProvider);
    final keys = state.entries
        .where(
          (entry) =>
              entry.value.serverId == serverId &&
              names.contains(entry.value.name),
        )
        .map((entry) => entry.key)
        .toList();
    for (final key in keys) {
      await repo.delete(key);
    }
    state = repo.get();
  }
}
