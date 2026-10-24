import 'dart:io';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/parser/booruonrails_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/e621_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/safebooru_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/shimmie_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/szurubooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/xml_entry.dart';
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

const _server = Server(
  id: 'Test',
  homepage: 'https://example.com',
  postUrl: 'post/{post-id}',
);

const _gelbooruXmlServer = Server(
  id: 'GelbooruXml',
  homepage: 'https://gelbooru.example.com',
  searchUrl:
      'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}',
  searchParserId: 'Gelbooru.xml',
);

Response _response(Object? data) =>
    Response(requestOptions: RequestOptions(), data: data);

Map<String, dynamic> _gelbooruEntry({
  int id = 1,
  Object? width = 100,
  Object? height = 100,
  String previewUrl = 'https://cdn.example.com/1-thumb.jpg',
  String sampleUrl = '',
}) {
  return {
    'id': id,
    'file_url': 'https://cdn.example.com/\$id.jpg',
    'preview_url': previewUrl,
    'sample_url': sampleUrl,
    'width': width,
    'height': height,
    'tags': 'a b',
  };
}

void main() async {
  setupLogger(test: true);
  setupMocktailFallbacks();
  TestWidgetsFlutterBinding.ensureInitialized();

  group('XML text nodes are trimmed', () {
    test('the gelbooru fixture keeps every media url', () {
      final payload = File(
        'test/fixtures/gelbooru/posts.xml',
      ).readAsStringSync();

      final page = GelbooruXmlParser().parsePage(_server, _response(payload));

      // Two of the five entries carry no preview_url, so they fail the guard.
      expect(page.rawCount, 5);
      expect(page.posts, hasLength(3));
      for (final post in page.posts) {
        expect(post.previewFile, startsWith('https://'));
        expect(post.previewFile, post.previewFile.trim());
        expect(post.originalFile, startsWith('https://'));
      }

      // The one entry with a sample is also missing its preview, so the sample
      // is checked on the parsed entry rather than on a published post.
      final entries = xmlEntries(payload, 'post')!;
      final sample = entries
          .map((it) => it['sample_url'])
          .whereType<String>()
          .firstWhere((it) => it.isNotEmpty);
      expect(sample, startsWith('https://'));
      expect(sample, sample.trim());
    });

    test('attribute values are trimmed too', () {
      const payload =
          '<posts count="1">'
          '<post id="1" file_url=" https://cdn.example.com/1.jpg " '
          'preview_url="https://cdn.example.com/1-thumb.jpg " '
          'width="100" height="200"/>'
          '</posts>';

      final page = SafebooruXmlParser().parsePage(_server, _response(payload));

      expect(page.single.originalFile, 'https://cdn.example.com/1.jpg');
      expect(page.single.previewFile, 'https://cdn.example.com/1-thumb.jpg');
    });
  });

  group('an empty result set is recognised by the parsers', () {
    test('a root without an entry element', () {
      expect(
        xmlIsEmptyResultSet('<?xml version="1.0"?><posts count="0"/>'),
        isTrue,
      );
    });

    test('a childless entry element', () {
      expect(
        xmlIsEmptyResultSet(
          '<?xml version="1.0"?><posts count="0"><post></post></posts>',
        ),
        isTrue,
      );
    });

    test('an entry carrying values is not empty', () {
      const payload =
          '<?xml version="1.0"?><posts count="1">'
          '<post fileurl="https://cdn.example.com/1.jpg"/></posts>';
      expect(xmlIsEmptyResultSet(payload), isFalse);
    });

    test('a payload that is not XML is not an empty result', () {
      expect(xmlIsEmptyResultSet('<html><body>502'), isFalse);
      expect(xmlIsEmptyResultSet(42), isFalse);
    });

    test('every XML reader answers the same way', () {
      const payload = '<?xml version="1.0"?><posts count="0"/>';
      for (final parser in [
        GelbooruXmlParser(),
        SafebooruXmlParser(),
        ShimmieXmlParser(),
      ]) {
        expect(parser.isEmptyPayload(_response(payload)), isTrue);
      }
    });
  });

  group('szurubooru safety is mapped to a rating', () {
    ({String safety, String rating}) caseOf(String safety) {
      final res = _response({
        'results': [
          {
            'id': 1,
            'contentUrl': 'https://cdn.example.com/1.jpg',
            'thumbnailUrl': 'https://cdn.example.com/1-thumb.jpg',
            'canvasWidth': 100,
            'canvasHeight': 200,
            'safety': safety,
            'tags': [],
          },
        ],
      });
      final posts = SzurubooruJsonParser().parsePage(_server, res);
      return (safety: safety, rating: posts.single.rateValue);
    }

    test('safe, sketchy and unsafe become s, q and e', () {
      expect(caseOf('safe').rating, 's');
      expect(caseOf('sketchy').rating, 'q');
      expect(caseOf('unsafe').rating, 'e');
    });

    test('an unknown grade falls back to the pipeline default', () {
      expect(caseOf('').rating, 'q');
      expect(caseOf('sensitive').rating, 'q');
    });
  });

  group('a single-entry envelope is read as one entry', () {
    test('gelbooru', () {
      final page = GelbooruJsonParser().parsePage(
        _server,
        _response({'post': _gelbooruEntry()}),
      );
      expect(page.posts, hasLength(1));
      expect(page.rawCount, 1);
    });

    test('booru on rails', () {
      final page = BooruOnRailsJsonParser().parsePage(
        _server,
        _response({
          'images': {
            'id': 1,
            'view_url': 'https://cdn.example.com/1.jpg',
            'representations': {'thumb': 'https://cdn.example.com/1-thumb.jpg'},
            'width': 100,
            'height': 200,
            'tags': ['safe'],
          },
        }),
      );
      expect(page.posts, hasLength(1));
      expect(page.rawCount, 1);
    });

    test('szurubooru', () {
      final page = SzurubooruJsonParser().parsePage(
        _server,
        _response({
          'results': {
            'id': 1,
            'contentUrl': 'https://cdn.example.com/1.jpg',
            'thumbnailUrl': 'https://cdn.example.com/1-thumb.jpg',
            'canvasWidth': 100,
            'canvasHeight': 200,
            'safety': 'safe',
            'tags': [],
          },
        }),
      );
      expect(page.posts, hasLength(1));
      expect(page.rawCount, 1);
    });

    test(
      'an entry of an unusable type yields no entry instead of throwing',
      () {
        final page = GelbooruJsonParser().parsePage(
          _server,
          _response({'post': 'nope'}),
        );
        expect(page.posts, isEmpty);
        expect(page.rawCount, 0);
      },
    );
  });

  group('e621 only claims a post list', () {
    test('a null posts value is not a parseable page', () {
      final res = _response({'posts': null});
      expect(E621JsonParser().canParsePage(res), isFalse);
      expect(E621JsonParser().isEmptyPayload(res), isTrue);
    });

    test('a posts list is parseable', () {
      final res = _response({'posts': []});
      expect(E621JsonParser().canParsePage(res), isTrue);
    });
  });

  group('danbooru sniffers never throw', () {
    test('a list of strings matches no shape', () {
      final res = _response(['a', 'b']);
      expect(DanbooruJsonParser().canParsePage(res), isFalse);
      expect(DanbooruJsonParser().canParseSuggestion(res), isFalse);
    });

    test('a list of scalars matches no shape', () {
      final res = _response([1, null, <String>[]]);
      expect(DanbooruJsonParser().canParsePage(res), isFalse);
      expect(DanbooruJsonParser().canParseSuggestion(res), isFalse);
    });
  });

  group('XML sniffers do not require a document prolog', () {
    test('gelbooru', () {
      const payload =
          '<posts count="1"><post><file_url>https://cdn.example.com/1.jpg'
          '</file_url></post></posts>';
      expect(GelbooruXmlParser().canParsePage(_response(payload)), isTrue);
    });

    test('safebooru', () {
      const payload =
          '<posts count="1">'
          '<post file_url="https://cdn.example.com/1.jpg" '
          'preview_url="https://cdn.example.com/1-thumb.jpg"/></posts>';
      expect(SafebooruXmlParser().canParsePage(_response(payload)), isTrue);
    });

    test('shimmie', () {
      const payload =
          '<posts count="1"><tag file_url="https://cdn.example.com/1.jpg"/>'
          '</posts>';
      expect(ShimmieXmlParser().canParsePage(_response(payload)), isTrue);
    });
  });

  group('numeric dimensions', () {
    test(
      'a non-integer dimension is truncated instead of dropping the post',
      () {
        final page = GelbooruJsonParser().parsePage(
          _server,
          _response({
            'post': [_gelbooruEntry(width: 992.0, height: 1228.5)],
          }),
        );

        expect(page.posts, hasLength(1));
        expect(page.single.width, 992);
        expect(page.single.height, 1228);
      },
    );
  });

  test('an entry whose media cannot be normalized is dropped', () {
    final page = GelbooruJsonParser().parsePage(
      _server,
      _response({
        'post': [
          _gelbooruEntry(previewUrl: 'ht tp://cdn.example.com/1-thumb.jpg'),
        ],
      }),
    );

    // rawCount still counts the entry, so pagination does not read the page as
    // the end of the results.
    expect(page.posts, isEmpty);
    expect(page.rawCount, 1);
  });

  group('szurubooru suggestions', () {
    test('an entry without names is skipped', () {
      final suggestions = SzurubooruJsonParser().parseSuggestion(
        _server,
        _response({
          'results': [
            {'names': <String>[], 'usages': 5},
            {
              'names': ['book'],
              'usages': 3,
            },
          ],
        }),
      );

      expect(suggestions, hasLength(1));
      expect(suggestions.single.name, 'book');
    });
  });
  group('an empty XML page is a result, not a failure', () {
    test('a childless entry does not reach the error state', () async {
      final ref = ProviderContainer(
        overrides: [envRepoProvider.overrideWithValue(FakeEnvRepo())],
      );
      addTearDown(ref.dispose);
      ref.setupTestFor(dioProvider);
      final adapter = DioAdapterMock(ref.read(dioProvider));
      ref.setupTestFor(imageboardRepoProvider(_gelbooruXmlServer));

      when(() => adapter.fetch(any(), any(), any())).thenAnswer(
        (_) async => ResponseBody.fromString(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<posts count="0" offset="0"><post></post></posts>',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/xml'],
          },
        ),
      );

      final posts = await ref
          .read(imageboardRepoProvider(_gelbooruXmlServer))
          .getPage(const PageOption(limit: 10), 0);

      expect(posts, isEmpty);
    });
  });
}
