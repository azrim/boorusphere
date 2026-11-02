import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/tags_blocker/tag_expression.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_cache.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/text_match.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'suggestion_state.g.dart';

class Suggestion {
  const Suggestion(this.name, this.count, [this.category]);

  final String name;
  final int count;

  /// The category the server reported for this tag, or null when the engine's
  /// suggestion payload does not carry one.
  final TagCategory? category;
}

/// Orders two suggestions for the same [word]: closer completion first, then
/// the more used tag, then the shorter one.
int compareSuggestions(Suggestion a, Suggestion b, String word) {
  final byRank = matchRank(a.name, word).compareTo(matchRank(b.name, word));
  if (byRank != 0) return byRank;

  final byCount = b.count.compareTo(a.count);
  if (byCount != 0) return byCount;

  final byLength = a.name.length.compareTo(b.name.length);
  if (byLength != 0) return byLength;

  return a.name.compareTo(b.name);
}

@riverpod
class SuggestionState extends _$SuggestionState {
  SuggestionState({this.session = const SearchSession()});

  final SearchSession session;

  String? _lastWord;

  @override
  FetchResult<Iterable<Suggestion>> build() {
    _lastWord = null;
    return const FetchResult.idle([]);
  }

  String _lastWordOf(String query) {
    final queries = query.toWordList();
    if (queries.isEmpty || query.endsWith(' ')) {
      return '';
    }

    return queries.last;
  }

  Future<void> get(String query) async {
    final word = _lastWordOf(query);

    // Don't fetch suggestions for very short queries to reduce API load.
    if (word.length < 2) {
      _lastWord = word;
      state = const FetchResult.data([]);
      return;
    }

    final server = ref.read(serverStateProvider).getById(session.serverId);
    if (server == Server.empty) {
      state = const FetchResult.data([]);
      return;
    }

    final cache = ref.read(suggestionCacheProvider);
    final cached = cache.get(server.id, word);
    if (cached != null) {
      // The list was shown before; putting it back is instant and costs no
      // request. It also runs when the bar reopens on the word already on
      // screen, so a tag blocked meanwhile is filtered out again instead of
      // staying on offer. The blockers are applied in [_publish] because they
      // can have changed since the answer was stored.
      _lastWord = word;
      _publish(cached, word, server);
      return;
    }

    // Claim the word before the request so a slower answer for an older
    // prefix is dropped instead of replacing the list the reader is looking at.
    _lastWord = word;
    state = FetchResult.loading(state.data);
    try {
      final res = await ref
          .read(imageboardRepoProvider(server))
          .getSuggestion(word);
      final suggestions = res.toList();
      // Cache the answer even when the reader has already typed past it: it is
      // still the answer for this word, and the next revisit should not wait.
      cache.put(server.id, word, suggestions);
      // The search bar can close while the answer is on the wire. The element
      // is gone by then and every write below would throw — including the one
      // in the catch, whose error escapes this future uncaught.
      if (!ref.mounted || word != _lastWord) return;

      _publish(suggestions, word, server);
    } catch (err, stack) {
      if (!ref.mounted || word != _lastWord) {
        return;
      }
      state = FetchResult.error(state.data, error: err, stackTrace: stack);
    }
  }

  /// Filters, dedupes and sorts [suggestions] for [word], then publishes them.
  ///
  /// Scoped like the timeline: a tag blocked on one server is still a usable
  /// tag on the others. Only a single positive term names a tag that can be
  /// judged on its own; a combination (`foo bar`, `-foo`) says nothing about
  /// one suggestion.
  void _publish(Iterable<Suggestion> suggestions, String word, Server server) {
    final blockedNames = <String>{};
    for (final it in ref.read(tagsBlockerStateProvider).values) {
      if (it.serverId.isNotEmpty && it.serverId != server.id) continue;
      final tag = BlockedTagExpression.parse(it.name).singlePositiveTag;
      if (tag != null) blockedNames.add(tag);
    }

    final seen = <String>{};
    final result =
        suggestions
            .where((it) => !blockedNames.contains(it.name.toLowerCase()))
            .where((it) => seen.add(it.name))
            .where((it) => matchRank(it.name, word) < kNoMatch)
            .toList()
          ..sort((a, b) => compareSuggestions(a, b, word));

    if (result.isEmpty) {
      state = FetchResult.error(state.data, error: BooruError.empty);
      return;
    }

    state = FetchResult.data(result);
  }
}
