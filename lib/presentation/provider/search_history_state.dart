import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/text_match.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'search_history_state.g.dart';

/// History entries to show for [query], best match first.
///
/// The map keeps insertion order and that order is the display order: entries
/// are ranked by where the typed text sits in the stored query (exact, prefix,
/// later word, substring) instead of by recency alone. Typing `anime` used to
/// leave `anime_screenshot` below older multi-tag searches that merely
/// contained the word; recency now only breaks a tie.
///
/// A query with one tag also outranks a longer query at the same match
/// position: `animated` and `anime_screenshot` answer the typed word on their
/// own, while `anime_screenshot chiyu_mahou` only starts with it and would
/// otherwise win on recency alone.
@riverpod
Map<int, SearchHistory> filterHistory(Ref ref, String query) {
  // Already newest-first: the notifier sorts once per change instead of this
  // provider copying and sorting the whole history on every keystroke.
  final history = ref.watch(searchHistoryStateProvider);
  final entries = history.entries.toList();

  final typed = query.trim();
  // A trailing space means the reader is starting the next tag.
  if (typed.isEmpty || query.endsWith(' ')) {
    return Map.fromEntries(entries);
  }

  final word = typed.toWordList().last;
  final matched = entries
      .where((it) => matchRank(it.value.query, word) < kNoMatch)
      .toList();
  matched.sort((a, b) {
    final byRank = matchRank(
      a.value.query,
      word,
    ).compareTo(matchRank(b.value.query, word));
    if (byRank != 0) return byRank;
    final byTags = a.value.query.toWordList().length.compareTo(
      b.value.query.toWordList().length,
    );
    if (byTags != 0) return byTags;
    return b.key.compareTo(a.key);
  });

  return Map.fromEntries(matched);
}

/// Kept alive because an undo toast lives on the root messenger: the row it
/// restores may be long gone from the screen when the action runs, and a
/// disposed notifier could not write it back.
@Riverpod(keepAlive: true)
class SearchHistoryState extends _$SearchHistoryState {
  @override
  Map<int, SearchHistory> build() {
    final repo = ref.read(searchHistoryRepoProvider);
    // Newest first, once per change. Hive hands out incrementing keys, and a
    // reused query is re-added under a higher one, so key order is recency
    // order. Every consumer (the unfiltered list and the ranked filter) gets
    // the same base order without sorting again.
    return _newestFirst(repo.all);
  }

  Map<int, SearchHistory> _newestFirst(Map<int, SearchHistory> entries) {
    final keys = entries.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final key in keys) key: entries[key]!};
  }

  Future<void> save(String value, Server server) async {
    final repo = ref.read(searchHistoryRepoProvider);
    await repo.save(value.trim(), server.id);
    state = _newestFirst(repo.all);
  }

  Future<void> delete(key) async {
    final repo = ref.read(searchHistoryRepoProvider);
    await repo.delete(key);
    state = _newestFirst(repo.all);
  }

  /// Puts a dismissed entry back as it was, count and key included, so an undo
  /// does not read as a new search in its usage count or its position.
  Future<void> restore(int key, SearchHistory entry) async {
    final repo = ref.read(searchHistoryRepoProvider);
    await repo.restore(key, entry);
    state = _newestFirst(repo.all);
  }

  Future<void> clear() async {
    final repo = ref.read(searchHistoryRepoProvider);
    await repo.clear();
    state = _newestFirst(repo.all);
  }
}
