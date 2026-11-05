import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
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
  searchUrl: 'api/posts?offset={post-offset}&limit={post-limit}&query={tags}',
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

  Future<ParsedPage> pageFor(Server server, String body) async {
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

  group('a page that failed is not a page with nothing on it', () {
    test('one tag with a broken escape keeps the posts beside it', () async {
      // Percent-decoding a tag name happens after the payload was read and
      // throws on a damaged escape, which the repository used to answer as one
      // more empty page. The reader takes an empty page for the end of the
      // results and stops asking, so a single un-decodable tag threw away the
      // posts that came with it.
      final page = await pageFor(
        _gelbooru,
        '{"post":['
        '{"id":1,"file_url":"https://cdn.test/1.jpg",'
        '"preview_url":"https://cdn.test/1-preview.jpg","width":10,'
        '"height":10,"tags":"cat"},'
        '{"id":2,"file_url":"https://cdn.test/2.jpg",'
        '"preview_url":"https://cdn.test/2-preview.jpg","width":10,'
        '"height":10,"tags":"%FF dog"}]}',
      );

      expect(page.rawCount, 2);
      expect(page.posts, hasLength(2));
      expect(
        page.posts.firstWhere((it) => it.id == 2).tags,
        contains('%FF'),
        reason: 'the tag the decoder could not read stays as it was written',
      );
    });

    test('a backend answer where the entries should be fails loudly', () async {
      // A scalar under the entry key is neither an entry nor an empty result
      // set. Calling it empty stopped pagination on a query the very next
      // request answers with posts.
      expect(
        () => pageFor(_gelbooru, '{"post":"backend timeout"}'),
        throwsA(BooruError.unparsable),
      );
    });

    test(
      'a scalar envelope is not an empty result for another engine either',
      () async {
        // The dispatcher asks every parser whether the payload is empty, so
        // one engine's over-reading became every engine's: any known entry key
        // carrying text silenced the whole app.
        expect(
          () => pageFor(_szurubooru, '{"results":"backend timeout"}'),
          throwsA(BooruError.unparsable),
        );
      },
    );

    test('an exhausted result set still reads as one', () async {
      // The control: the shape that really does mean "no more" keeps meaning
      // that, so these three fixes do not turn an end of results into an error.
      expect(await pageFor(_gelbooru, '{"post":[]}'), isEmpty);
      expect(await pageFor(_szurubooru, '{"results":[],"total":0}'), isEmpty);
    });
  });
}
