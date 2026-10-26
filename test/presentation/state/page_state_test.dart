import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
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
    return pages[index] ?? const ParsedPage.empty();
  }
}

class _FakeServerState extends ServerState {
  @override
  Iterable<Server> build() => [_server];
}

class _FakeServerSetting extends ServerSettingState {
  _FakeServerSetting(this.limit);

  final int limit;

  @override
  ServerSetting build() {
    return ServerSetting(
      lastActiveId: _server.id,
      postLimit: limit,
      searchRating: BooruRating.safe,
    );
  }
}

class _FakeTagsBlocker extends TagsBlockerState {
  _FakeTagsBlocker(this.blocked);

  final List<String> blocked;

  @override
  Map<int, BooruTag> build() {
    return {
      for (var i = 0; i < blocked.length; i++) i: BooruTag(name: blocked[i]),
    };
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
  int limit = 4,
  List<String> blocked = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      serverStateProvider.overrideWith(_FakeServerState.new),
      serverSettingStateProvider.overrideWith(() => _FakeServerSetting(limit)),
      tagsBlockerStateProvider.overrideWith(() => _FakeTagsBlocker(blocked)),
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
    final container = _container(repo, limit: 4);
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
}
