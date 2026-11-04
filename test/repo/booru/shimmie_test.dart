import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/parser/shimmie_xml_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
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

void main() async {
  setupLogger(test: true);
  setupMocktailFallbacks();
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveTestContainer hiveContainer;

  setUpAll(() async {
    // One Hive container per file: the adapters are global, so registering
    // them a second time throws.
    hiveContainer = HiveTestContainer();
    await UserServerRepo.prepare();
  });

  tearDownAll(() async {
    await hiveContainer.dispose();
  });

  Future<(ProviderContainer, DioAdapterMock)> createHarness() async {
    final ref = ProviderContainer(
      overrides: [
        defaultServersProvider.overrideWithValue(await provideDefaultServers()),
        envRepoProvider.overrideWithValue(FakeEnvRepo()),
      ],
    );
    addTearDown(ref.dispose);

    ref.setupTestFor(dioProvider);
    final adapter = DioAdapterMock(ref.read(dioProvider));

    ref.setupTestFor(serverRepoProvider);
    await ref.read(serverRepoProvider).populate();

    return (ref, adapter);
  }

  final parser = ShimmieXmlParser();
  Server paheal() => Server(
    homepage: 'https://rule34.paheal.net',
    searchUrl: parser.searchQuery,
    tagSuggestionUrl: parser.suggestionQuery,
  );

  const option = PageOption(limit: 5, searchRating: BooruRating.all);

  test('Shimmie', () async {
    final (ref, adapter) = await createHarness();

    const fakePage = 'rule34.paheal/posts.xml';
    when(
      () => adapter.fetch(any(), any(), any()),
    ).thenAnswer((_) async => FakeResponseBody.fromFixture(fakePage, 200));

    final posts = await ref
        .read(imageboardRepoProvider(paheal()))
        .getPage(option, 1);
    expect(
      posts,
      isA<Iterable>().having((x) => x.length, 'total', option.limit - 2),
      reason: 'expecting 2 invalid post',
    );

    final first = posts.first;
    expect(first.id, 5754271);
    expect(first.width, 990);
    expect(first.height, 785);
    expect(first.rateValue, '?');

    const fakeTags = 'rule34.paheal/tags.json';
    when(
      () => adapter.fetch(any(), any(), any()),
    ).thenAnswer((_) async => FakeResponseBody.fromFixture(fakeTags, 200));

    expect(
      await ref.read(imageboardRepoProvider(paheal())).getSuggestion('book'),
      isA<Iterable>().having(
        (x) => x.length,
        'total',
        Server.tagSuggestionLimit - 2,
      ),
      reason: 'expecting 2 tags with zero post_count',
    );
  });

  test('Shimmie answers on its clean path, with tags inside the post', () async {
    final (ref, adapter) = await createHarness();

    when(() => adapter.fetch(any(), any(), any())).thenAnswer(
      (_) async =>
          FakeResponseBody.fromFixture('rule34.paheal/posts-modern.xml', 200),
    );

    final posts = await ref
        .read(imageboardRepoProvider(paheal()))
        .getPage(option, 1);

    // Both fixtures are captures from the live site: the entry element is now
    // `<post>` and the tag list rides in its `tags` attribute. Reading only the
    // old spelling found nothing, and `/index.xml` answers an error page.
    expect(posts, hasLength(4));
    expect(posts.first.id, 7494083);
    expect(posts.first.width, 3840);
    expect(posts.first.height, 2160);
    expect(posts.first.rateValue, '?');
    expect(posts.first.tags, contains('Floragato'));

    final requested =
        verify(() => adapter.fetch(captureAny(), any(), any())).captured.first
            as RequestOptions;
    expect(
      requested.uri.path,
      '/api/danbooru/find_posts',
      reason: 'the .xml suffix now resolves to an HTML error page',
    );

    when(() => adapter.fetch(any(), any(), any())).thenAnswer(
      (_) async =>
          FakeResponseBody.fromFixture('rule34.paheal/tags-modern.json', 200),
    );

    final suggestions = await ref
        .read(imageboardRepoProvider(paheal()))
        .getSuggestion('cat');

    expect(suggestions, hasLength(25));
    expect(
      suggestions.firstWhere((it) => it.name == 'Cat').count,
      485,
      reason: 'current installs count inside the tag object',
    );
  });
}
