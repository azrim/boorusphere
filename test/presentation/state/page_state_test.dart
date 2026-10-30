import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/search_history_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/entity/server_setting.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _server = Server(
  id: 'S',
  homepage: 'https://s.test',
  searchUrl: 'x?tags={tags}&pid={page-id}&limit={post-limit}',
);

Post _post(int id, {String tag = 'ok'}) {
  return Post(
    id: id,
    originalFile: 'https://s.test/$id.jpg',
    previewFile: 'https://s.test/$id.p.jpg',
    width: 10,
    height: 10,
    serverId: 'S',
    tags: [tag],
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

  @override
  Future<Iterable<Suggestion>> getSuggestion(String query) async => [];

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

ProviderContainer _container(
  ImageboardRepo repo, {
  _Window? window,
  List<String> blocked = const [],
  String blockerServerId = '',
  TagsBlockerState? blocker,
  ServerState? servers,
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
      searchHistoryStateProvider.overrideWith(_FakeSearchHistory.new),
      pageStateProvider.overrideWith(
        () => PageState(session: const SearchSession(serverId: 'S')),
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
}
