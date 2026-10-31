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
  final history = ref.watch(searchHistoryStateProvider);
  // Hive hands out incrementing keys, so the highest key is the newest search.
  final entries = history.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));

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

@riverpod
class SearchHistoryState extends _$SearchHistoryState {
  @override
  Map<int, SearchHistory> build() {
    final repo = ref.read(searchHistoryRepoProvider);
    return repo.all;
  }

  Future<void> save(String value, Server server) async {
    final repo = ref.read(searchHistoryRepoProvider);
    await repo.save(value.trim(), server.id);
    state = repo.all;
  }

  Future<void> delete(key) async {
    final repo = ref.read(searchHistoryRepoProvider);
    await repo.delete(key);
    state = repo.all;
  }

  Future<void> clear() async {
    final repo = ref.read(searchHistoryRepoProvider);
    await repo.clear();
    state = repo.all;
  }
}
