import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import '../../presentation/state/app_version_test.dart';
import '../../utils/dio.dart';
import '../../utils/mocktail.dart';
import '../../utils/riverpod.dart';

const _szurubooru = Server(
  id: 'Szurubooru',
  homepage: 'https://szuru.example.com',
  searchUrl: 'api/posts/?offset={post-offset}&limit={post-limit}&query={tags}',
  searchParserId: 'Szurubooru.json',
);

const _gelbooru = Server(
  id: 'Gelbooru',
  homepage: 'https://gelbooru.com',
  searchUrl:
      'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}&json=1',
  searchParserId: 'Gelbooru.json',
);

void main() async {
  setupLogger(test: true);
  setupMocktailFallbacks();
  TestWidgetsFlutterBinding.ensureInitialized();

  const option = PageOption(limit: 10);

  Future<ProviderContainer> createRef() async {
    final ref = ProviderContainer(
      overrides: [envRepoProvider.overrideWithValue(FakeEnvRepo())],
    );
    ref.setupTestFor(dioProvider);
    return ref;
  }

  Future<Iterable<dynamic>> pageFor(Server server, String body) async {
    final ref = await createRef();
    addTearDown(ref.dispose);
    final adapter = DioAdapterMock(ref.read(dioProvider));
    ref.setupTestFor(imageboardRepoProvider(server));
    when(() => adapter.fetch(any(), any(), any())).thenAnswer(
      (_) async => ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    return ref.read(imageboardRepoProvider(server)).getPage(option, 0);
  }

  group('empty payloads are results, not parse failures', () {
    test(
      'szurubooru keeps its envelope when the result set is exhausted',
      () async {
        expect(await pageFor(_szurubooru, '{"results":[],"total":0}'), isEmpty);
      },
    );

    test('gelbooru answers with the attributes envelope alone', () async {
      final posts = await pageFor(
        _gelbooru,
        '{"@attributes":{"limit":100,"offset":0,"count":0}}',
      );
      expect(posts, isEmpty);
    });

    test('an unreadable payload still fails loudly', () async {
      expect(
        () => pageFor(_gelbooru, '{"error":"rate limited"}'),
        throwsA(BooruError.unparsable),
      );
    });
  });
}
