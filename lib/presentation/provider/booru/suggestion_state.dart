import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'suggestion_state.g.dart';

class Suggestion {
  final String name;
  final int count;

  const Suggestion(this.name, this.count);
}

@riverpod
class SuggestionState extends _$SuggestionState {
  final SearchSession session;

  SuggestionState({this.session = const SearchSession()});

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
      final res =
          await ref.read(imageboardRepoProvider(server)).getSuggestion(word);
      final blockedTags = ref.read(tagsBlockerRepoProvider);
      final result = res
          .where((it) =>
              !blockedTags.get().values.map((e) => e.name).contains(it.name))
          .toList();
      result.sort((a, b) => b.count.compareTo(a.count));
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
