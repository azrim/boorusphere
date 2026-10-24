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

const _gelbooruXml = Server(
  id: 'GelbooruXml',
  homepage: 'https://gelbooru.example.com',
  searchUrl:
      'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}',
  searchParserId: 'Gelbooru.xml',
);

/// A well-formed result set whose post attributes no parser reads.
String _xmlPage(int count, {String fileAttribute = 'file_url'}) {
  final entries = List.generate(
    count,
    (i) =>
        '<post id="${i + 1}" $fileAttribute="https://x/${i + 1}.jpg" '
        'preview_url="https://x/${i + 1}.p.jpg" width="10" height="10"/>',
  ).join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<posts count="$count" offset="0">$entries</posts>';
}

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

    test('an XML result set with no entry at all is empty', () async {
      final posts = await pageFor(
        _gelbooruXml,
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<posts count="0" offset="0"/>',
      );
      expect(posts, isEmpty);
    });

    test('an XML result set no parser can read is a parse failure', () async {
      // 40 entries are present, so this must not be reported as "no results":
      // that answer would end pagination for the whole query.
      expect(
        () => pageFor(_gelbooruXml, _xmlPage(40, fileAttribute: 'fileurl')),
        throwsA(BooruError.unparsable),
      );
    });
  });
}
