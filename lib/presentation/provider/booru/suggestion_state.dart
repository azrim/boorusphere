import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'suggestion_state.g.dart';

/// Boorus typically use `_` as the word separator in tag names (e.g.
/// `hololive_girl`); we also accept literal spaces to defend against feeds
/// that emit pre-decoded labels.
final RegExp _kTagSeparator = RegExp(r'[ _]+');

class Suggestion {
  const Suggestion(this.name, this.count);

  final String name;
  final int count;
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
    if (_lastWord == word) {
      return;
    }

    // Don't fetch suggestions for very short queries to reduce API load
    if (word.length < 2) {
      state = const FetchResult.data([]);
      _lastWord = word;
      return;
    }

    final server = ref.read(serverStateProvider).getById(session.serverId);
    if (server == Server.empty) {
      state = const FetchResult.data([]);
      return;
    }

    state = FetchResult.loading(state.data);
    _lastWord = word;
    try {
      final res = await ref
          .read(imageboardRepoProvider(server))
          .getSuggestion(word);
      final blockedTags = ref.read(tagsBlockerRepoProvider);
      final blockedNames = blockedTags.get().values.map((e) => e.name).toSet();
      final result = res
          .where((it) => !blockedNames.contains(it.name))
          .toList();
      // Sort single-word tags before multi-word tags (booru tags use `_` as
      // the word separator, but treat literal spaces the same way for
      // robustness). Within the same word count, fall back to post count
      // descending so the most popular variant surfaces first.
      int wordCount(String s) {
        final t = s.trim();
        if (t.isEmpty) return 0;
        return t.split(_kTagSeparator).where((w) => w.isNotEmpty).length;
      }

      result.sort((a, b) {
        final byWords = wordCount(a.name).compareTo(wordCount(b.name));
        if (byWords != 0) return byWords;
        return b.count.compareTo(a.count);
      });
      if (word != _lastWord) return;

      if (result.isEmpty && word.isNotEmpty) {
        state = FetchResult.error(state.data, error: BooruError.empty);
        return;
      }

      state = FetchResult.data(result);
    } catch (err, stack) {
      if (word != _lastWord) {
        return;
      }
      state = FetchResult.error(state.data, error: err, stackTrace: stack);
    }
  }
}
