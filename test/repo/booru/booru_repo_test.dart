import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import '../../presentation/state/app_version_test.dart';
import '../../utils/dio.dart';
import '../../utils/hive.dart';
import '../../utils/mocktail.dart';
import '../../utils/riverpod.dart';

/// A Danbooru-flavoured [Server]; `searchParserId`/`suggestionParserId` are the
/// only knobs the dispatch tests need to flip.
Server _danbooruServer({
  String searchParserId = '',
  String suggestionParserId = '',
}) {
  return Server(
    id: 'Danbooru',
    homepage: 'https://danbooru.donmai.us',
    postUrl: 'posts/{post-id}',
    searchUrl: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
    tagSuggestionUrl:
        'tags.json?search[name_matches]=*{tag-part}*&search[order]=count&limit={post-limit}',
    searchParserId: searchParserId,
    suggestionParserId: suggestionParserId,
  );
}

/// A Gelbooru-shaped server used to prove the dispatcher sniffs a *different*
/// parser than the id-configured one.
Server _gelbooruServer({String searchParserId = ''}) {
  return Server(
    id: 'Gelbooru',
    homepage: 'https://gelbooru.com',
    postUrl: 'index.php?page=post&s=view&id={post-id}',
    searchUrl:
        'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}&json=1',
    searchParserId: searchParserId,
  );
}

void main() async {
  setupLogger(test: true);
  setupMocktailFallbacks();
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveTestContainer hiveContainer;

  setUpAll(() async {
    hiveContainer = HiveTestContainer();
    await UserServerRepo.prepare();
  });

  tearDownAll(() async {
    await hiveContainer.dispose();
  });

  Future<ProviderContainer> createRef() async {
    final ref = ProviderContainer(
      overrides: [
        defaultServersProvider.overrideWithValue(await provideDefaultServers()),
        envRepoProvider.overrideWithValue(FakeEnvRepo()),
      ],
    );
    ref.setupTestFor(dioProvider);
    return ref;
  }

  const option = PageOption(limit: 5);

  group('BooruRepo parser dispatch', () {
    test('uses the id-configured search parser', () async {
      final ref = await createRef();
      addTearDown(ref.dispose);
      final adapter = DioAdapterMock(ref.read(dioProvider));

      final server = _danbooruServer(searchParserId: 'Danbooru.json');
      ref.setupTestFor(imageboardRepoProvider(server));

      when(() => adapter.fetch(any(), any(), any())).thenAnswer(
        (_) async => FakeResponseBody.fromFixture('danbooru/posts.json', 200),
      );

      final posts = await ref
          .read(imageboardRepoProvider(server))
          .getPage(option, 1);

      expect(
        posts,
        isA<Iterable>().having((x) => x.length, 'total', option.limit - 2),
        reason: 'expecting 2 invalid post',
      );
      expect(posts.first.id, 6402984);
      expect(posts.first.serverId, 'Danbooru');
    });

    test(
      'falls back to sniffing when the id-configured parser cannot parse',
      () async {
        final ref = await createRef();
        addTearDown(ref.dispose);
        final adapter = DioAdapterMock(ref.read(dioProvider));

        // Gelbooru.json is configured, but the payload is a Danbooru list.
        final server = _gelbooruServer(searchParserId: 'Gelbooru.json');
        ref.setupTestFor(imageboardRepoProvider(server));

        when(() => adapter.fetch(any(), any(), any())).thenAnswer(
          (_) async => FakeResponseBody.fromFixture('danbooru/posts.json', 200),
        );

        final posts = await ref
            .read(imageboardRepoProvider(server))
            .getPage(option, 1);

        expect(
          posts,
          isA<Iterable>().having((x) => x.length, 'total', option.limit - 2),
          reason: 'expecting 2 invalid post',
        );
        // Sniffed by the Danbooru parser, yet still bound to the Gelbooru server.
        expect(posts.first.id, 6402984);
        expect(posts.first.serverId, 'Gelbooru');
      },
    );

    test('sniffs a parser when no id is configured', () async {
      final ref = await createRef();
      addTearDown(ref.dispose);
      final adapter = DioAdapterMock(ref.read(dioProvider));

      final server = _danbooruServer();
      ref.setupTestFor(imageboardRepoProvider(server));

      when(() => adapter.fetch(any(), any(), any())).thenAnswer(
        (_) async => FakeResponseBody.fromFixture('danbooru/posts.json', 200),
      );

      final posts = await ref
          .read(imageboardRepoProvider(server))
          .getPage(option, 1);

      expect(
        posts,
        isA<Iterable>().having((x) => x.length, 'total', option.limit - 2),
        reason: 'expecting 2 invalid post',
      );
      expect(posts.first.id, 6402984);
    });

    test('sniffs a parser when the configured id is unknown', () async {
      final ref = await createRef();
      addTearDown(ref.dispose);
      final adapter = DioAdapterMock(ref.read(dioProvider));

      final server = _danbooruServer(searchParserId: 'Nope');
      ref.setupTestFor(imageboardRepoProvider(server));

      when(() => adapter.fetch(any(), any(), any())).thenAnswer(
        (_) async => FakeResponseBody.fromFixture('danbooru/posts.json', 200),
      );

      final posts = await ref
          .read(imageboardRepoProvider(server))
          .getPage(option, 1);

      expect(
        posts,
        isA<Iterable>().having((x) => x.length, 'total', option.limit - 2),
        reason: 'expecting 2 invalid post',
      );
      expect(posts.first.id, 6402984);
    });

    test('uses the id-configured suggestion parser', () async {
      final ref = await createRef();
      addTearDown(ref.dispose);
      final adapter = DioAdapterMock(ref.read(dioProvider));

      final server = _danbooruServer(suggestionParserId: 'Danbooru.json');
      ref.setupTestFor(imageboardRepoProvider(server));

      when(() => adapter.fetch(any(), any(), any())).thenAnswer(
        (_) async => FakeResponseBody.fromFixture('danbooru/tags.json', 200),
      );

      final suggestions = await ref
          .read(imageboardRepoProvider(server))
          .getSuggestion('book');

      expect(
        suggestions,
        isA<Iterable>().having(
          (x) => x.length,
          'total',
          Server.tagSuggestionLimit - 2,
        ),
        reason: 'expecting 2 tags with zero post_count',
      );
    });

    test('returns an empty result when no parser matches', () async {
      final ref = await createRef();
      addTearDown(ref.dispose);
      final adapter = DioAdapterMock(ref.read(dioProvider));

      final server = _danbooruServer();
      ref.setupTestFor(imageboardRepoProvider(server));

      // An empty JSON list matches no parser; the repo must not throw.
      when(
        () => adapter.fetch(any(), any(), any()),
      ).thenAnswer((_) async => ResponseBody.fromString('[]', 200));

      final posts = await ref
          .read(imageboardRepoProvider(server))
          .getPage(option, 1);

      expect(posts, isEmpty);
    });
  });
}
