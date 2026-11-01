import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/booru/tag_info_cache.dart';
import 'package:boorusphere/presentation/provider/booru/tag_info_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _server = Server(
  id: 'S',
  homepage: 'https://s.test',
  searchUrl: 'posts.json?tags={tags}&page={page-num}&limit={post-limit}',
);

TagInfo _info(String tag, {int posts = 1}) =>
    TagInfo(name: tag, postCount: posts);

class _FakeRepo implements ImageboardRepo {
  int calls = 0;
  bool fail = false;

  /// Tags the fake was asked about, in order.
  final requested = <String>[];

  @override
  Server get server => _server;

  @override
  Future<Iterable<Suggestion>> getSuggestion(String query) async => const [];

  @override
  Future<ParsedPage> getPage(PageOption option, int index) async =>
      const ParsedPage.empty();

  @override
  Future<TagInfo> getTagInfo(String tag) async {
    calls++;
    requested.add(tag);
    if (fail) throw BooruError.unparsable;
    return _info(tag);
  }
}

class _FakeServerState extends ServerState {
  @override
  Iterable<Server> build() => [_server];
}

ProviderContainer _container(_FakeRepo repo) {
  return ProviderContainer(
    overrides: [
      serverStateProvider.overrideWith(_FakeServerState.new),
      imageboardRepoProvider(_server).overrideWithValue(repo),
    ],
  );
}

void main() {
  group('TagInfoCache', () {
    test('an answer is served until its entry expires', () {
      var now = DateTime(2026, 1, 1);
      final cache = TagInfoCache(
        ttl: const Duration(minutes: 15),
        clock: () => now,
      );
      cache.put('S', 'cat', _info('cat'));

      expect(cache.get('S', 'cat'), isNotNull);

      now = now.add(const Duration(minutes: 16));
      expect(cache.get('S', 'cat'), isNull);
    });

    test('the least recently used tag is dropped first', () {
      final cache = TagInfoCache(maxEntries: 2);
      cache.put('S', 'a', _info('a'));
      cache.put('S', 'b', _info('b'));

      // Reading `a` makes `b` the least recently used entry.
      expect(cache.get('S', 'a'), isNotNull);
      cache.put('S', 'c', _info('c'));

      expect(cache.get('S', 'b'), isNull);
      expect(cache.get('S', 'a'), isNotNull);
      expect(cache.get('S', 'c'), isNotNull);
    });

    test('server and casing both scope an entry', () {
      final cache = TagInfoCache();
      cache.put('S', 'Cat', _info('Cat'));

      expect(cache.get('S', ' cat '), isNotNull);
      expect(cache.get('Other', 'cat'), isNull);
    });

    test('removing one entry leaves the rest', () {
      final cache = TagInfoCache();
      cache.put('S', 'a', _info('a'));
      cache.put('S', 'b', _info('b'));

      cache.remove('S', 'a');

      expect(cache.get('S', 'a'), isNull);
      expect(cache.get('S', 'b'), isNotNull);
    });
  });

  group('tagInfoProvider', () {
    /// Keeps the element alive the way the open sheet does, so an async build
    /// is not disposed mid-flight.
    ProviderContainer listening(_FakeRepo repo, TagInfoQuery query) {
      final container = _container(repo);
      final sub = container.listen(
        tagInfoProvider(query),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      addTearDown(container.dispose);
      return container;
    }

    test(
      'a reopen is answered from the cache without a second request',
      () async {
        final repo = _FakeRepo();
        const query = TagInfoQuery(serverId: 'S', tag: 'cat');
        final container = listening(repo, query);

        final first = await container.read(tagInfoProvider(query).future);
        // Closing the sheet disposes the element; the next open builds anew.
        container.invalidate(tagInfoProvider(query));
        final second = await container.read(tagInfoProvider(query).future);

        expect(repo.calls, 1);
        expect(first.name, 'cat');
        expect(second.postCount, first.postCount);
      },
    );

    test('the casing of a tag does not open a second entry', () async {
      final repo = _FakeRepo();
      const query = TagInfoQuery(serverId: 'S', tag: 'Cat');
      final container = listening(repo, query);

      await container.read(tagInfoProvider(query).future);
      container.invalidate(tagInfoProvider(query));
      await container.read(
        tagInfoProvider(const TagInfoQuery(serverId: 'S', tag: ' cat ')).future,
      );

      expect(repo.calls, 1);
    });

    test('a failure is not cached, so the next open asks again', () async {
      final repo = _FakeRepo()..fail = true;
      const query = TagInfoQuery(serverId: 'S', tag: 'cat');
      final container = listening(repo, query);

      await expectLater(
        container.read(tagInfoProvider(query).future),
        throwsA(BooruError.unparsable),
      );

      repo.fail = false;
      container.invalidate(tagInfoProvider(query));
      final info = await container.read(tagInfoProvider(query).future);

      expect(info.name, 'cat');
      expect(repo.calls, 2);
    });

    test('an explicit retry goes back to the wire', () async {
      final repo = _FakeRepo();
      const query = TagInfoQuery(serverId: 'S', tag: 'cat');
      final container = listening(repo, query);

      await container.read(tagInfoProvider(query).future);
      // The retry action drops the entry before invalidating the element.
      container.read(tagInfoCacheProvider).remove('S', 'cat');
      container.invalidate(tagInfoProvider(query));
      await container.read(tagInfoProvider(query).future);

      expect(repo.calls, 2);
    });

    test('an unknown server is unsupported and costs no request', () async {
      final repo = _FakeRepo();
      const query = TagInfoQuery(serverId: 'gone', tag: 'cat');
      final container = listening(repo, query);

      await expectLater(
        container.read(tagInfoProvider(query).future),
        throwsA(BooruError.tagInfoUnsupported),
      );
      expect(repo.calls, 0);
    });
  });
}
