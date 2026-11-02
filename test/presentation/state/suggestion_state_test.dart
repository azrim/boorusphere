import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _server = Server(id: 'S', homepage: 'https://s.test');

/// Answers every word once one gate is opened, so a test can hold a request on
/// the wire while the search bar goes away.
class _FakeRepo implements ImageboardRepo {
  _FakeRepo([this.answers = const {}]);

  final Map<String, List<Suggestion>> answers;
  final gate = Completer<void>();

  /// How many times the fake went to the wire; the cache is proven by this
  /// staying flat on a repeated word.
  int calls = 0;

  /// When set, the awaited answer fails instead, which exercises the catch.
  bool fail = false;

  @override
  Server get server => _server;

  @override
  Future<ParsedPage> getPage(PageOption option, int index) async =>
      const ParsedPage.empty();

  @override
  Future<TagInfo> getTagInfo(String tag) async => TagInfo(name: tag);

  @override
  Future<Iterable<Suggestion>> getSuggestion(String query) async {
    calls++;
    await gate.future;
    if (fail) throw Exception('suggestions unavailable');
    return answers[query] ?? const [];
  }
}

class _FakeServerState extends ServerState {
  @override
  Iterable<Server> build() => [_server];
}

class _FakeTagsBlocker extends TagsBlockerState {
  _FakeTagsBlocker([Iterable<String> blocked = const []])
    : blocked = [...blocked];

  final List<String> blocked;

  @override
  Map<int, BooruTag> build() {
    return {
      for (var i = 0; i < blocked.length; i++)
        i: BooruTag(serverId: '', name: blocked[i]),
    };
  }

  /// Adds [tags] to the blocker set the way the blocker screen does.
  void block(Iterable<String> tags) {
    blocked.addAll(tags);
    state = build();
  }
}

ProviderContainer _container(ImageboardRepo repo, {TagsBlockerState? blocker}) {
  final container = ProviderContainer(
    overrides: [
      serverStateProvider.overrideWith(_FakeServerState.new),
      tagsBlockerStateProvider.overrideWith(
        () => blocker ?? _FakeTagsBlocker(),
      ),
      suggestionStateProvider.overrideWith(
        () => SuggestionState(session: const SearchSession(serverId: 'S')),
      ),
      imageboardRepoProvider(_server).overrideWithValue(repo),
    ],
  );
  // The bar itself keeps the element alive while it is open.
  container.listen(suggestionStateProvider, (_, _) {}, fireImmediately: true);
  return container;
}

void main() {
  test('an answer that lands after the bar closed does not throw', () async {
    final repo = _FakeRepo(const {
      'cat': [Suggestion('cat', 1)],
    });
    final container = _container(repo);
    final notifier = container.read(suggestionStateProvider.notifier);

    final pending = notifier.get('cat');
    container.dispose();
    repo.gate.complete();

    await pending;
  });

  test('a failure after the bar closed does not escape the fetch', () async {
    // The catch used to write the state again, so a disposed element threw
    // twice: once inside the catch and once out of the caller's hands.
    final repo = _FakeRepo();
    repo.fail = true;
    final container = _container(repo);
    final notifier = container.read(suggestionStateProvider.notifier);

    final pending = notifier.get('cat');
    container.dispose();
    repo.gate.complete();

    await pending;
  });

  test('an answer for the word on screen is published', () async {
    final repo = _FakeRepo(const {
      'cat': [Suggestion('cat_ear', 3), Suggestion('cat', 9)],
    });
    final container = _container(repo);
    addTearDown(container.dispose);
    final notifier = container.read(suggestionStateProvider.notifier);

    final pending = notifier.get('cat');
    repo.gate.complete();
    await pending;

    expect(container.read(suggestionStateProvider).data.map((it) => it.name), [
      'cat',
      'cat_ear',
    ]);
  });

  test('a word seen before is served from the cache', () async {
    final repo = _FakeRepo(const {
      'cat': [Suggestion('cat_ear', 3)],
      'catt': [Suggestion('catt', 1)],
    });
    final container = _container(repo);
    addTearDown(container.dispose);
    final notifier = container.read(suggestionStateProvider.notifier);

    final first = notifier.get('cat');
    repo.gate.complete();
    await first;
    await notifier.get('catt');
    expect(repo.calls, 2);

    await notifier.get('cat');

    expect(repo.calls, 2);
    expect(container.read(suggestionStateProvider).data.map((it) => it.name), [
      'cat_ear',
    ]);
  });

  test('reopening on the same word drops a tag blocked since', () async {
    // The bar asks for suggestions again when it reopens on the word already
    // on screen. That used to return early and leave the old list, so a tag
    // blocked meanwhile stayed on offer and tapping it submitted a query the
    // feed refuses. The cached answer is re-published, which re-filters it
    // without another request.
    final repo = _FakeRepo(const {
      'cat': [Suggestion('cat', 9), Suggestion('cat_ear', 3)],
    });
    final blocker = _FakeTagsBlocker();
    final container = _container(repo, blocker: blocker);
    addTearDown(container.dispose);
    final notifier = container.read(suggestionStateProvider.notifier);

    final first = notifier.get('cat');
    repo.gate.complete();
    await first;
    expect(container.read(suggestionStateProvider).data.map((it) => it.name), [
      'cat',
      'cat_ear',
    ]);

    blocker.block(['cat_ear']);
    await notifier.get('cat');

    expect(container.read(suggestionStateProvider).data.map((it) => it.name), [
      'cat',
    ]);
    expect(repo.calls, 1);
  });
}
