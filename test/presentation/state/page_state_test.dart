import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/feed_filter_state.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/search_history_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/entity/server_setting.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _server = Server(
  id: 'S',
  homepage: 'https://s.test',
  searchUrl: 'x?tags={tags}&pid={page-id}&limit={post-limit}',
);

Post _post(int id, {String tag = 'ok', List<String> moreTags = const []}) {
  return Post(
    id: id,
    originalFile: 'https://s.test/$id.jpg',
    previewFile: 'https://s.test/$id.p.jpg',
    width: 10,
    height: 10,
    serverId: 'S',
    tags: [tag, ...moreTags],
  );
}

class _FakeRepo implements ImageboardRepo {
  _FakeRepo(this.pages);

  final Map<int, ParsedPage> pages;
  final requested = <int>[];

  /// When set, every fetch waits for it before answering.
  Completer<void>? gate;

  /// Page indexes whose fetch fails.
  final failing = <int>{};

  /// When set, pages at and beyond this index answer as if the server had no
  /// more entries: a result window that shrank under the reader.
  int? emptyFrom;

  @override
  Server get server => _server;

  /// Suggestions the fake server answers for any word.
  Iterable<Suggestion> suggestions = const [];

  @override
  Future<Iterable<Suggestion>> getSuggestion(String query) async => suggestions;

  @override
  Future<TagInfo> getTagInfo(String tag) async => TagInfo(name: tag);

  @override
  Future<ParsedPage> getPage(PageOption option, int index) async {
    requested.add(index);
    final pending = gate;
    if (pending != null) await pending.future;
    if (failing.contains(index)) throw Exception('page $index failed');
    final firstMissing = emptyFrom;
    if (firstMissing != null && index >= firstMissing) {
      return const ParsedPage.empty();
    }
    return pages[index] ?? const ParsedPage.empty();
  }
}

class _FakeServerState extends ServerState {
  Iterable<Server> list = const [_server];

  @override
  Iterable<Server> build() => list;

  /// Mirrors [ServerState.remove]: the drawer drops a server and every lookup
  /// has to answer from the new list.
  void replace(Iterable<Server> servers) {
    list = servers;
    state = servers;
  }
}

/// The result window the settings page writes and the timeline reads on every
/// fetch: a page index only means something together with these two.
class _Window {
  _Window({this.limit = 4});

  int limit;
  BooruRating rating = BooruRating.safe;
}

class _FakeServerSetting extends ServerSettingState {
  _FakeServerSetting(this.window);

  final _Window window;

  @override
  ServerSetting build() {
    return ServerSetting(
      lastActiveId: _server.id,
      postLimit: window.limit,
      searchRating: window.rating,
    );
  }

  @override
  Future<void> setPostLimit(int value) async {
    window.limit = value;
    state = state.copyWith(postLimit: value);
  }

  @override
  Future<void> setRating(BooruRating value) async {
    window.rating = value;
    state = state.copyWith(searchRating: value);
  }
}

/// A server list that cannot be read at all: the storage behind it failed.
class _UnreadableServerState extends ServerState {
  @override
  Iterable<Server> build() => throw Exception('server box unreadable');
}

class _FakeTagsBlocker extends TagsBlockerState {
  _FakeTagsBlocker(Iterable<String> blocked, {this.serverId = ''})
    : blocked = [...blocked];

  final List<String> blocked;

  /// The server the blockers belong to; empty for tags blocked on every
  /// booru.
  final String serverId;

  @override
  Map<int, BooruTag> build() {
    return {
      for (var i = 0; i < blocked.length; i++)
        i: BooruTag(serverId: serverId, name: blocked[i]),
    };
  }

  /// Adds [tags] to the blocker set the way the blocker screen does.
  void block(Iterable<String> tags) {
    blocked.addAll(tags);
    state = build();
  }
}

class _FakeSearchHistory extends SearchHistoryState {
  @override
  Map<int, SearchHistory> build() => {};

  @override
  Future<void> save(String value, Server server) async {}
}

/// Records every query the page counts, so a test can tell one search from a
/// reload of it.
class _CountingSearchHistory extends SearchHistoryState {
  final saved = <String>[];

  @override
  Map<int, SearchHistory> build() => {};

  @override
  Future<void> save(String value, Server server) async => saved.add(value);
}

/// A history box the app cannot write, the way a closed or corrupt box
/// behaves. Writing the history is a convenience, never a reason to fail the
/// page.
class _ThrowingSearchHistory extends SearchHistoryState {
  @override
  Map<int, SearchHistory> build() => {};

  @override
  Future<void> save(String value, Server server) async {
    throw Exception('history box unwritable');
  }
}

class _FakeUiSetting extends UiSettingState {
  _FakeUiSetting(this.mode);

  FeedMode mode;

  @override
  UiSetting build() => UiSetting(feedMode: mode);

  @override
  Future<FeedMode> setFeedMode(FeedMode value) async {
    mode = value;
    state = state.copyWith(feedMode: value);
    return value;
  }
}

ProviderContainer _container(
  ImageboardRepo repo, {
  _Window? window,
  List<String> blocked = const [],
  String blockerServerId = '',
  TagsBlockerState? blocker,
  ServerState? servers,
  Set<FeedPostKey> hidden = const {},
  FeedMode mode = FeedMode.paged,
  SearchHistoryState? history,
}) {
  final settings = window ?? _Window();
  final container = ProviderContainer(
    overrides: [
      serverStateProvider.overrideWith(() => servers ?? _FakeServerState()),
      serverSettingStateProvider.overrideWith(
        () => _FakeServerSetting(settings),
      ),
      tagsBlockerStateProvider.overrideWith(
        () => blocker ?? _FakeTagsBlocker(blocked, serverId: blockerServerId),
      ),
      searchHistoryStateProvider.overrideWith(
        () => history ?? _FakeSearchHistory(),
      ),
      uiSettingStateProvider.overrideWith(() => _FakeUiSetting(mode)),
      hiddenFeedPostKeysProvider.overrideWithValue(hidden),
      pageStateProvider.overrideWith(
        () => PageState(session: const SearchSession(serverId: 'S')),
      ),
      suggestionStateProvider.overrideWith(
        () => SuggestionState(session: const SearchSession(serverId: 'S')),
      ),
      imageboardRepoProvider(_server).overrideWithValue(repo),
    ],
  );
  container.listen(pageStateProvider, (_, _) {}, fireImmediately: true);
  return container;
}

void main() {
  test('a page shorter than the limit does not end pagination', () async {
    // The server clamps the requested page size, so every page is short even
    // though it still has more behind it.
    final repo = _FakeRepo({
      for (var i = 0; i < 3; i++)
        i: ParsedPage(posts: [_post(i * 2), _post(i * 2 + 1)], rawCount: 2),
    });
    final container = _container(repo, window: _Window(limit: 4));
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    expect(container.read(pageStateProvider).data.hasNext, isTrue);

    await notifier.nextPage();
    expect(container.read(pageStateProvider).data.pageIndex, 2);
    expect(container.read(pageStateProvider).data.hasNext, isTrue);
  });

  test('a literal empty page ends pagination', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1)], rawCount: 1),
    });
    final container = _container(repo);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    expect(container.read(pageStateProvider).data.hasNext, isTrue);

    await notifier.nextPage();
    expect(container.read(pageStateProvider).data.pageIndex, 1);
    expect(container.read(pageStateProvider).data.hasNext, isFalse);
  });

  test('a blocked first page leaves no previous page to offer', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1, tag: 'blocked')], rawCount: 1),
      1: ParsedPage(posts: [_post(2), _post(3)], rawCount: 2),
    });
    final container = _container(repo, blocked: ['blocked']);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    expect(container.read(pageStateProvider).data.pageIndex, 2);
    expect(container.read(pageStateProvider).data.hasPrev, isTrue);

    await notifier.prevPage();
    expect(container.read(pageStateProvider).data.pageIndex, 2);
    expect(container.read(pageStateProvider).data.hasPrev, isFalse);

    // The disabled control must not keep re-requesting the blocked page.
    final requestedBefore = repo.requested.length;
    await notifier.prevPage();
    expect(repo.requested.length, requestedBefore);
  });

  test('an AND blocker hides only posts that carry every tag', () async {
    final repo = _FakeRepo({
      0: ParsedPage(
        posts: [
          _post(1, tag: 'foo'),
          _post(2, tag: 'foo', moreTags: ['bar']),
          _post(3, tag: 'bar'),
        ],
        rawCount: 3,
      ),
    });
    final container = _container(repo, blocked: ['foo bar']);
    addTearDown(container.dispose);

    await container.read(pageStateProvider.notifier).load();

    expect(container.read(pageStateProvider).data.posts.map((it) => it.id), [
      1,
      3,
    ]);
  });

  test('an OR blocker hides posts with either tag', () async {
    final repo = _FakeRepo({
      0: ParsedPage(
        posts: [
          _post(1, tag: 'foo'),
          _post(2, tag: 'bar'),
          _post(3, tag: 'baz'),
        ],
        rawCount: 3,
      ),
    });
    final container = _container(repo, blocked: ['~foo ~bar']);
    addTearDown(container.dispose);

    await container.read(pageStateProvider.notifier).load();

    expect(container.read(pageStateProvider).data.posts.map((it) => it.id), [
      3,
    ]);
  });

  test('a negated blocker hides posts without the tag', () async {
    final repo = _FakeRepo({
      0: ParsedPage(
        posts: [
          _post(1, tag: 'foo'),
          _post(2, tag: 'ok'),
        ],
        rawCount: 2,
      ),
    });
    final container = _container(repo, blocked: ['-foo']);
    addTearDown(container.dispose);

    await container.read(pageStateProvider.notifier).load();

    expect(container.read(pageStateProvider).data.posts.map((it) => it.id), [
      1,
    ]);
  });

  test('an OR tag does not refuse a query that carries it', () async {
    // `~ok` does not always hide `ok`, so the guard must not reject the query
    // before asking the server the way a plain blocked tag would.
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1, tag: 'ok')], rawCount: 1),
    });
    final container = _container(repo, blocked: ['~ok']);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.update((option) => option.copyWith(query: 'ok'));

    expect(repo.requested, isNotEmpty);
    final result = container.read(pageStateProvider);
    expect(switch (result) {
      ErrorFetchResult(:final error) => error,
      _ => null,
    }, isNot(BooruError.tagsBlocked));
  });

  test(
    'a page emptied by a local filter is skipped like a blocked one',
    () async {
      // Favorited/downloaded filters work after the server answer. A whole page
      // of filtered posts would otherwise leave an empty grid with `hasNext`
      // still true.
      final repo = _FakeRepo({
        0: ParsedPage(posts: [_post(1), _post(2)], rawCount: 2),
        1: ParsedPage(posts: [_post(3)], rawCount: 1),
      });
      final container = _container(
        repo,
        window: _Window(limit: 2),
        hidden: {(serverId: 'S', id: 1), (serverId: 'S', id: 2)},
      );
      addTearDown(container.dispose);
      final notifier = container.read(pageStateProvider.notifier);

      await notifier.load();

      expect(repo.requested, [0, 1]);
      final data = container.read(pageStateProvider).data;
      expect(data.posts.map((it) => it.id), [3]);
      expect(data.pageIndex, 2);
      expect(data.hasPrev, isTrue);
      expect(data.hasNext, isTrue);
    },
  );

  test('a partly filtered page keeps its visible posts', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1), _post(2)], rawCount: 2),
    });
    final container = _container(
      repo,
      window: _Window(limit: 2),
      hidden: {(serverId: 'S', id: 1)},
    );
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();

    final data = container.read(pageStateProvider).data;
    expect(data.posts.map((it) => it.id), [2]);
    expect(data.pageIndex, 1);
    // The server still returned a full page, so more results may follow even
    // though only one post survived the filter.
    expect(data.hasNext, isTrue);
  });

  test('suggestions hide tags blocked by a single positive entry', () async {
    final repo = _FakeRepo({})
      ..suggestions = const [Suggestion('foobar', 10), Suggestion('fooqux', 5)];
    // `foo bar` decides over a combination, so it cannot hide one suggestion;
    // `~foobar` names a tag on its own and must hide it.
    final container = _container(repo, blocked: ['foo bar', '~foobar']);
    addTearDown(container.dispose);
    final notifier = container.read(suggestionStateProvider.notifier);

    await notifier.get('foo');

    final result = container.read(suggestionStateProvider);
    final names = switch (result) {
      DataFetchResult(:final data) => data.map((it) => it.name).toList(),
      _ => <String>[],
    };
    expect(names, ['fooqux']);
  });

  test('pagination refuses a query blocked after it loaded', () async {
    // The query passed the guard when it was loaded. Blocking one of its tags
    // afterwards has to stop the next page as well: it is still a page of the
    // same blocked query.
    final repo = _FakeRepo({
      for (var i = 0; i < 4; i++) i: ParsedPage(posts: [_post(i)], rawCount: 1),
    });
    final blocker = _FakeTagsBlocker(const []);
    final container = _container(repo, blocker: blocker);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.update((option) => option.copyWith(query: 'ok'));
    expect(container.read(pageStateProvider).data.pageIndex, 1);

    blocker.block(['ok']);
    repo.requested.clear();
    await notifier.nextPage();

    final refused = container.read(pageStateProvider);
    expect(refused, isA<ErrorFetchResult>());
    expect(switch (refused) {
      ErrorFetchResult(:final error) => error,
      _ => null,
    }, BooruError.tagsBlocked);
    expect(repo.requested, isEmpty);
  });

  test('a retry refuses a query blocked after it loaded', () async {
    // A failed page leaves a retry aimed at the page the user asked for. That
    // retry is a way into a fetch too, so it runs the same guard.
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1)], rawCount: 1),
      1: ParsedPage(posts: [_post(2)], rawCount: 1),
    });
    final blocker = _FakeTagsBlocker(const []);
    final container = _container(repo, blocker: blocker);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.update((option) => option.copyWith(query: 'ok'));
    repo.failing.add(1);
    await notifier.nextPage();
    expect(container.read(pageStateProvider), isA<ErrorFetchResult>());

    blocker.block(['ok']);
    repo.requested.clear();
    repo.failing.clear();
    await notifier.load();

    final refused = container.read(pageStateProvider);
    expect(refused, isA<ErrorFetchResult>());
    expect(switch (refused) {
      ErrorFetchResult(:final error) => error,
      _ => null,
    }, BooruError.tagsBlocked);
    expect(repo.requested, isEmpty);
  });

  test('a failed jump past the end keeps the next page on offer', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1)], rawCount: 1),
      1: ParsedPage(posts: [_post(2)], rawCount: 1),
    });
    final container = _container(repo);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    await notifier.goToPage(5);
    expect(container.read(pageStateProvider).data.pageIndex, 1);
    // The jump proved nothing about the page directly behind this one.
    expect(container.read(pageStateProvider).data.hasNext, isTrue);

    await notifier.nextPage();
    expect(container.read(pageStateProvider).data.pageIndex, 2);
  });

  test('a fetch that lands after the page is gone does not throw', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1)], rawCount: 1),
    });
    repo.gate = Completer<void>();
    final container = _container(repo);
    final notifier = container.read(pageStateProvider.notifier);

    final loading = notifier.load();
    container.dispose();
    repo.gate!.complete();
    await loading;
  });

  test('an option queued behind a failed fetch is applied', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1)], rawCount: 1),
      1: ParsedPage(posts: [_post(2)], rawCount: 1),
    });
    final container = _container(repo);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);
    await notifier.load();

    repo.gate = Completer<void>();
    repo.failing.add(1);
    final nav = notifier.nextPage();
    // Queued while the navigation is still on the wire, and newer than the
    // request that is about to fail.
    await notifier.update((it) => it.copyWith(limit: 8));
    repo.gate!.complete();
    repo.gate = null;
    await nav;
    await pumpEventQueue();

    // The queued option wins: the page it restarts is fetched again instead of
    // the navigation that just failed being retried.
    expect(repo.requested.last, 0);
    expect(container.read(pageStateProvider).data.pageIndex, 1);
  });

  test('a page change queued during a fetch is not dropped', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1)], rawCount: 1),
    });
    repo.gate = Completer<void>();
    final container = _container(repo);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    final first = notifier.load();
    await notifier.update((it) => it.copyWith(query: 'cat', clear: true));
    await notifier.update((it) => it.copyWith(clear: true));
    repo.gate!.complete();
    await first;
    await pumpEventQueue();

    expect(container.read(pageStateProvider).data.option.query, 'cat');
  });

  test('a rating switch restarts the first page', () async {
    // The rating is part of the result window: the same page index addresses
    // other posts once the safe-only list is swapped for another one, so a
    // reload must not hand back the page the old window landed on.
    final repo = _FakeRepo({
      for (var i = 0; i < 4; i++) i: ParsedPage(posts: [_post(i)], rawCount: 1),
    });
    final window = _Window();
    final container = _container(repo, window: window);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    await notifier.nextPage();
    await notifier.nextPage();
    expect(container.read(pageStateProvider).data.pageIndex, 3);

    await container
        .read(serverSettingStateProvider.notifier)
        .setRating(BooruRating.explicit);
    repo.requested.clear();
    await notifier.load();

    expect(repo.requested, [0]);
    expect(container.read(pageStateProvider).data.pageIndex, 1);
  });

  test(
    'a rating picked during a fetch reaches the feed once it settles',
    () async {
      // The chip writes the setting and then asks for a reload. That reload
      // lands while the page request is still on the wire, so the request that
      // finishes carries the rating read before the pick.
      final repo = _FakeRepo({
        for (var i = 0; i < 4; i++)
          i: ParsedPage(posts: [_post(i)], rawCount: 1),
      });
      final window = _Window();
      final container = _container(repo, window: window);
      addTearDown(container.dispose);
      final notifier = container.read(pageStateProvider.notifier);
      await notifier.load();

      repo.gate = Completer<void>();
      final nav = notifier.nextPage();
      await container
          .read(serverSettingStateProvider.notifier)
          .setRating(BooruRating.explicit);
      await notifier.load();
      repo.gate!.complete();
      repo.gate = null;
      await nav;
      await pumpEventQueue();

      final data = container.read(pageStateProvider).data;
      expect(data.option.searchRating, BooruRating.explicit);
      expect(data.pageIndex, 1);
      expect(data.hasPrev, isFalse);
    },
  );

  test('a deep page that came back empty asks the first page first', () async {
    final repo = _FakeRepo({
      for (var i = 0; i < 3; i++) i: ParsedPage(posts: [_post(i)], rawCount: 1),
    });
    final container = _container(repo);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    await notifier.nextPage();
    await notifier.nextPage();
    expect(container.read(pageStateProvider).data.pageIndex, 3);

    // The window shrank under the reader: the landed page is past the end now,
    // which says nothing about the query having no results at all.
    repo.emptyFrom = 1;
    repo.requested.clear();
    await notifier.load();

    expect(repo.requested, [2, 0]);
    expect(container.read(pageStateProvider).data.pageIndex, 1);
    expect(container.read(pageStateProvider).data.hasPrev, isFalse);
  });

  test('a failed window reset steps through the new window', () async {
    final repo = _FakeRepo({
      for (var i = 0; i < 4; i++) i: ParsedPage(posts: [_post(i)], rawCount: 1),
    });
    final window = _Window();
    final container = _container(repo, window: window);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    await notifier.nextPage();
    await notifier.nextPage();
    expect(container.read(pageStateProvider).data.pageIndex, 3);

    // The page size doubles, so the next step restarts from the first page of
    // the new window. That reset now fails, but it already moved the landed
    // page back: the step after it must ask for the page behind the first one,
    // not for the old index in the new window.
    await container.read(serverSettingStateProvider.notifier).setPostLimit(8);
    repo.failing.add(0);
    await notifier.nextPage();
    expect(repo.requested, [0, 1, 2, 0]);

    repo.failing.clear();
    repo.requested.clear();
    await notifier.nextPage();

    expect(repo.requested, [1]);
    expect(container.read(pageStateProvider).data.pageIndex, 2);
  });

  test('a failed window reset names the first page of the new window', () async {
    // The reset moves the landed page back before its request fails. The error
    // card has to name that page: keeping the old number and an enabled back
    // arrow would offer a step the restarted window cannot take.
    final repo = _FakeRepo({
      for (var i = 0; i < 4; i++) i: ParsedPage(posts: [_post(i)], rawCount: 1),
    });
    final window = _Window();
    final container = _container(repo, window: window);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    await notifier.nextPage();
    await notifier.nextPage();
    expect(container.read(pageStateProvider).data.pageIndex, 3);

    await container
        .read(serverSettingStateProvider.notifier)
        .setRating(BooruRating.explicit);
    repo.failing.add(0);
    await notifier.load();

    final failed = container.read(pageStateProvider);
    expect(failed, isA<ErrorFetchResult>());
    expect(failed.data.pageIndex, 1);
    expect(failed.data.hasPrev, isFalse);

    repo.requested.clear();
    await notifier.prevPage();
    expect(repo.requested, isEmpty);

    repo.failing.clear();
    await notifier.nextPage();
    expect(repo.requested, [1]);
    expect(container.read(pageStateProvider).data.pageIndex, 2);
  });

  test('a server lost mid-fetch keeps its blockers', () async {
    // Blockers are scoped to the booru the request went to. Resolving them
    // again after every await would read the empty server the session lost and
    // publish a post that the asked booru blocks.
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1, tag: 'blocked')], rawCount: 1),
      1: ParsedPage(posts: [_post(2, tag: 'blocked')], rawCount: 1),
    });
    final servers = _FakeServerState();
    final container = _container(
      repo,
      servers: servers,
      blocked: ['blocked'],
      blockerServerId: _server.id,
    );
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    repo.gate = Completer<void>();
    final loading = notifier.load();
    servers.replace(const []);
    repo.gate!.complete();
    await loading;

    expect(repo.requested, [0, 1, 2]);
    expect(container.read(pageStateProvider).data.posts, isEmpty);
  });

  test('a server list that cannot be read reports an error', () async {
    // Resolving the session server reads storage. Left uncaught, the throw
    // escaped the load and the feed stayed `idle` — a state the timeline
    // renders as nothing at all, with no retry to get out.
    final repo = _FakeRepo({});
    final container = _container(repo, servers: _UnreadableServerState());
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();

    expect(container.read(pageStateProvider), isA<ErrorFetchResult>());
    expect(repo.requested, isEmpty);
  });

  test('infinite mode appends the next page instead of replacing it', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1), _post(2)], rawCount: 2),
      1: ParsedPage(posts: [_post(2), _post(3)], rawCount: 2),
    });
    final container = _container(
      repo,
      window: _Window(limit: 2),
      mode: FeedMode.infinite,
    );
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    expect(container.read(pageStateProvider).data.posts.map((it) => it.id), [
      1,
      2,
    ]);

    await notifier.nextPage();

    expect(repo.requested, [0, 1]);
    final data = container.read(pageStateProvider).data;
    // Post 2 arrived on both pages: an overlap is kept once.
    expect(data.posts.map((it) => it.id), [1, 2, 3]);
    expect(data.hasNext, isTrue);
    expect(data.pageIndex, 2);
  });

  test(
    'infinite mode stops at a literal empty page and keeps the list',
    () async {
      final repo = _FakeRepo({
        0: ParsedPage(posts: [_post(1), _post(2)], rawCount: 2),
      });
      final container = _container(
        repo,
        window: _Window(limit: 2),
        mode: FeedMode.infinite,
      );
      addTearDown(container.dispose);
      final notifier = container.read(pageStateProvider.notifier);

      await notifier.load();
      await notifier.nextPage();

      final data = container.read(pageStateProvider).data;
      expect(data.posts.map((it) => it.id), [1, 2]);
      expect(data.hasNext, isFalse);

      // The end is final until a reload; the footer must not keep asking.
      final requestedBefore = repo.requested.length;
      await notifier.loadMore();
      expect(repo.requested.length, requestedBefore);
    },
  );

  test('infinite mode skips a page emptied by blocked tags', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1), _post(2)], rawCount: 2),
      1: ParsedPage(posts: [_post(3, tag: 'blocked')], rawCount: 1),
      2: ParsedPage(posts: [_post(4)], rawCount: 1),
    });
    final container = _container(
      repo,
      window: _Window(limit: 2),
      blocked: ['blocked'],
      mode: FeedMode.infinite,
    );
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    await notifier.nextPage();

    expect(repo.requested, [0, 1, 2]);
    final data = container.read(pageStateProvider).data;
    expect(data.posts.map((it) => it.id), [1, 2, 4]);
    expect(data.pageIndex, 3);
  });

  test(
    'a window change restarts an infinite list instead of appending',
    () async {
      final repo = _FakeRepo({
        for (var i = 0; i < 4; i++)
          i: ParsedPage(posts: [_post(i)], rawCount: 1),
      });
      final window = _Window();
      final container = _container(
        repo,
        window: window,
        mode: FeedMode.infinite,
      );
      addTearDown(container.dispose);
      final notifier = container.read(pageStateProvider.notifier);

      await notifier.load();
      await notifier.nextPage();
      expect(container.read(pageStateProvider).data.posts, hasLength(2));

      await container
          .read(serverSettingStateProvider.notifier)
          .setRating(BooruRating.explicit);
      repo.requested.clear();
      await notifier.nextPage();

      // The old page index addresses different posts under the new window, so
      // the list starts over from its first page rather than gluing the two.
      expect(repo.requested, [0]);
      final data = container.read(pageStateProvider).data;
      expect(data.posts.map((it) => it.id), [0]);
      expect(data.option.searchRating, BooruRating.explicit);
    },
  );

  test('a failed append is retried as an append, keeping the list', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1), _post(2)], rawCount: 2),
      1: ParsedPage(posts: [_post(3)], rawCount: 1),
    });
    final container = _container(
      repo,
      window: _Window(limit: 2),
      mode: FeedMode.infinite,
    );
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    repo.failing.add(1);
    await notifier.nextPage();

    final failed = container.read(pageStateProvider);
    expect(failed, isA<ErrorFetchResult>());
    expect(failed.data.posts.map((it) => it.id), [1, 2]);

    repo.failing.clear();
    await notifier.load();

    expect(repo.requested, [0, 1, 1]);
    final data = container.read(pageStateProvider).data;
    expect(data.posts.map((it) => it.id), [1, 2, 3]);
  });

  test('infinite mode stops at the in-memory ceiling', () async {
    final first = List.generate(
      PageState.maxAccumulatedPosts - 50,
      (i) => _post(i + 1),
    );
    final second = List.generate(100, (i) => _post(1000 + i));
    final repo = _FakeRepo({
      0: ParsedPage(posts: first, rawCount: first.length),
      1: ParsedPage(posts: second, rawCount: second.length),
    });
    final container = _container(repo, mode: FeedMode.infinite);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    expect(container.read(pageStateProvider).data.limitReached, isFalse);

    await notifier.nextPage();

    final data = container.read(pageStateProvider).data;
    expect(data.posts, hasLength(PageState.maxAccumulatedPosts));
    expect(data.limitReached, isTrue);

    // The ceiling is a local limit, not the server's end: no further request.
    await notifier.loadMore();
    expect(repo.requested, [0, 1]);
  });

  test(
    'a reload resets the infinite ceiling so the list can start over',
    () async {
      final first = List.generate(
        PageState.maxAccumulatedPosts - 50,
        (i) => _post(i + 1),
      );
      final second = List.generate(100, (i) => _post(1000 + i));
      final repo = _FakeRepo({
        0: ParsedPage(posts: first, rawCount: first.length),
        1: ParsedPage(posts: second, rawCount: second.length),
      });
      final container = _container(repo, mode: FeedMode.infinite);
      addTearDown(container.dispose);
      final notifier = container.read(pageStateProvider.notifier);

      await notifier.load();
      await notifier.nextPage();
      expect(container.read(pageStateProvider).data.limitReached, isTrue);

      // Pull-to-refresh is what the footer asks for. It restarts the list,
      // and the ceiling has to go with the list it was measured on.
      await notifier.load();

      final restarted = container.read(pageStateProvider).data;
      expect(restarted.posts, hasLength(first.length));
      expect(restarted.limitReached, isFalse);

      // The restarted list can grow again, up to its own ceiling.
      await notifier.loadMore();
      expect(repo.requested, [0, 1, 0, 1]);
      final grown = container.read(pageStateProvider).data;
      expect(grown.posts, hasLength(PageState.maxAccumulatedPosts));
      expect(grown.limitReached, isTrue);
    },
  );

  test('a stale infinite ceiling does not block a paged step', () async {
    // The ceiling is local to the accumulated list. A reader who switches to
    // the paged feed while the mode-switch reload fails would otherwise keep
    // the flag on the error data, and the pagination control stayed dead.
    final first = List.generate(
      PageState.maxAccumulatedPosts - 50,
      (i) => _post(i + 1),
    );
    final second = List.generate(100, (i) => _post(1000 + i));
    final repo = _FakeRepo({
      0: ParsedPage(posts: first, rawCount: first.length),
      1: ParsedPage(posts: second, rawCount: second.length),
    });
    final container = _container(repo, mode: FeedMode.infinite);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    await notifier.nextPage();
    expect(container.read(pageStateProvider).data.limitReached, isTrue);

    await container
        .read(uiSettingStateProvider.notifier)
        .setFeedMode(FeedMode.paged);
    repo.failing.add(0);
    await notifier.update((option) => option.copyWith(clear: true));
    expect(container.read(pageStateProvider), isA<ErrorFetchResult>());
    expect(container.read(pageStateProvider).data.limitReached, isTrue);

    repo.failing.clear();
    repo.requested.clear();
    await notifier.nextPage();

    expect(repo.requested, [1]);
    final data = container.read(pageStateProvider).data;
    expect(data.pageIndex, 2);
    expect(data.limitReached, isFalse);
  });

  test('a failing history write does not fail the page', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1)], rawCount: 1),
    });
    final container = _container(repo, history: _ThrowingSearchHistory());
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.update((option) => option.copyWith(query: 'cat'));
    // The write fails on its own microtask; it must neither hold the page
    // back nor turn into a feed error.
    await pumpEventQueue();

    expect(repo.requested, [0]);
    final result = container.read(pageStateProvider);
    expect(result, isA<DataFetchResult>());
    expect(result.data.posts.map((it) => it.id), [1]);
  });

  test('a search is counted once, not once per reload', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1)], rawCount: 1),
    });
    final history = _CountingSearchHistory();
    final container = _container(repo, history: history);
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.update((option) => option.copyWith(query: 'cat'));
    // A pull-to-refresh and a reload of the same query are the same search;
    // counting them inflated the usage a suggestion row reports.
    await notifier.load();
    await notifier.load();
    expect(history.saved, ['cat']);

    await notifier.update((option) => option.copyWith(query: 'dog'));
    expect(history.saved, ['cat', 'dog']);
  });

  test('loadMore leaves a paged feed alone', () async {
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1), _post(2)], rawCount: 2),
      1: ParsedPage(posts: [_post(3)], rawCount: 1),
    });
    final container = _container(repo, window: _Window(limit: 2));
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    await notifier.loadMore();

    expect(repo.requested, [0]);
    expect(container.read(pageStateProvider).data.posts.map((it) => it.id), [
      1,
      2,
    ]);
  });

  test('only a reload restarts the infinite feed, not an append', () async {
    // The viewport follows this counter: an append must leave the reader where
    // they are, while a reload that starts the list over — even when it lands
    // on the same first page — has to move them back to the top.
    final repo = _FakeRepo({
      0: ParsedPage(posts: [_post(1), _post(2)], rawCount: 2),
      1: ParsedPage(posts: [_post(3)], rawCount: 1),
    });
    final container = _container(
      repo,
      window: _Window(limit: 2),
      mode: FeedMode.infinite,
    );
    addTearDown(container.dispose);
    final notifier = container.read(pageStateProvider.notifier);

    await notifier.load();
    final afterLoad = container.read(pageStateProvider).data.restartSerial;

    await notifier.nextPage();
    expect(
      container.read(pageStateProvider).data.restartSerial,
      afterLoad,
      reason: 'appending a page must not reset the viewport',
    );

    await notifier.load();
    final afterReload = container.read(pageStateProvider).data.restartSerial;
    expect(afterReload, greaterThan(afterLoad));

    // A reload while the list is already back on its first page still counts:
    // the reader may have scrolled down that page.
    await notifier.load();
    expect(
      container.read(pageStateProvider).data.restartSerial,
      greaterThan(afterReload),
    );
  });
}
