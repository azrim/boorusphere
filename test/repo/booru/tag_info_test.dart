import 'dart:convert';
import 'dart:typed_data';

import 'package:boorusphere/data/repository/booru/booru_repo.dart';
import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/e621_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/moebooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/dtext_summary.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _server = Server(id: 'Test', homepage: 'https://example.com');

const _danbooru = Server(
  id: 'Danbooru',
  homepage: 'https://danbooru.test',
  searchUrl: 'posts.json?tags={tags}&page={page-num}&limit={post-limit}',
);

const _gelbooru = Server(
  id: 'Gelbooru',
  homepage: 'https://gelbooru.test',
  searchUrl:
      'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}&json=1',
  login: 'user',
  apiKey: 'secret key',
);

Response _response(Object? data) =>
    Response(requestOptions: RequestOptions(), data: data);

/// Serves a canned answer per URL fragment and records what was asked.
class _TagAdapter implements HttpClientAdapter {
  _TagAdapter(this.routes);

  final Map<String, _Reply> routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final url = options.uri.toString();
    _Reply? reply;
    for (final entry in routes.entries) {
      if (url.contains(entry.key)) {
        reply = entry.value;
        break;
      }
    }
    if (reply == null) {
      return ResponseBody.fromString('not found', 404);
    }

    final body = reply.body;
    final payload = body is String ? body : jsonEncode(body);
    return ResponseBody.fromString(
      payload,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [
          body is String ? 'text/xml' : Headers.jsonContentType,
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Reply {
  const _Reply(this.body, {this.status = 200});

  final Object? body;
  final int status;
}

BooruRepo _repo(
  Server server,
  HttpClientAdapter adapter, {
  List<BooruParser>? parsers,
}) {
  final dio = Dio(BaseOptions(validateStatus: (it) => it == 200));
  dio.httpClientAdapter = adapter;
  return BooruRepo(
    parsers:
        parsers ??
        [
          DanbooruJsonParser(),
          GelbooruJsonParser(),
          MoebooruJsonParser(),
          E621JsonParser(),
        ],
    client: dio,
    server: server,
    serverState: ServerState(),
  );
}

void main() {
  group('Danbooru', () {
    final parser = DanbooruJsonParser();

    test('requests the entry, wiki, related tags and aliases', () {
      final request = parser.tagInfoRequest(_danbooru, 'cat girl')!;

      expect(
        request.infoUrl,
        'https://danbooru.test/tags.json?search[name]=cat%20girl&limit=1',
      );
      expect(
        request.wikiUrl,
        'https://danbooru.test/wiki_pages/cat%20girl.json',
      );
      expect(
        request.relatedUrl,
        'https://danbooru.test/related_tag.json?query=cat%20girl',
      );
      expect(
        request.aliasUrl,
        'https://danbooru.test/tag_aliases.json'
        '?search[antecedent_name]=cat%20girl&limit=20',
      );
    });

    test('reads the entry and leaves a miss without details', () {
      final res = _response([
        {'name': 'cat', 'post_count': 42, 'category': 5},
      ]);

      final info = parser.parseTagInfo('cat', res)!;
      expect(info.name, 'cat');
      expect(info.category, TagCategory.meta);
      expect(info.postCount, 42);
      expect(info.hasDetails, isTrue);

      final miss = parser.parseTagInfo('nothing', _response([]))!;
      expect(miss.name, 'nothing');
      expect(miss.hasDetails, isFalse);

      expect(parser.parseTagInfo('cat', _response('nope')), isNull);
    });

    test('reads the wiki, aliases and related entries', () {
      final wiki = parser.parseTagWiki(
        _response({'body': 'A [b]cat[/b] is a small feline. thumb #123'}),
      );
      expect(wiki, 'A cat is a small feline.');

      final aliases = parser.parseTagAliases(
        _response([
          {'status': 'active', 'consequent_name': 'kitty'},
          {'status': 'deleted', 'consequent_name': 'old_cat'},
          {'consequent_name': 'kitty'},
        ]),
      );
      expect(aliases, ['kitty']);

      final related = parser.parseRelatedTags(
        _response({
          'related_tags': [
            {
              'tag': {'name': 'feline', 'post_count': 10},
            },
            {
              'tag': {'name': 'kitty', 'post_count': 7},
            },
            {'tag': <String, dynamic>{}},
          ],
        }),
      );
      expect(related.map((it) => it.name), ['feline', 'kitty']);
      expect(related.map((it) => it.postCount), [10, 7]);
    });
  });

  group('Moebooru', () {
    final parser = MoebooruJsonParser();

    test('asks the tag and related endpoints', () {
      final request = parser.tagInfoRequest(_server, 'cat')!;
      expect(request.infoUrl, 'https://example.com/tag.json?name=cat&limit=20');
      expect(
        request.relatedUrl,
        'https://example.com/tag/related.json?tags=cat',
      );
      expect(request.wikiUrl, isNull);
    });

    test('picks the exact entry out of a wildcard answer', () {
      final res = _response([
        {'name': 'cat_ears', 'count': 100, 'type': 0},
        {'name': 'cat', 'count': 42, 'type': 4},
      ]);

      final info = parser.parseTagInfo('CAT', res)!;
      expect(info.name, 'cat');
      expect(info.category, TagCategory.character);
      expect(info.postCount, 42);
    });

    test('filters out a tag that is only a substring match', () {
      final info = parser.parseTagInfo(
        'cat',
        _response([
          {'name': 'cat_ears', 'count': 100, 'type': 0},
        ]),
      )!;

      expect(info.name, 'cat');
      expect(info.hasDetails, isFalse);
    });

    test('reads numeric and string counts from related pairs', () {
      final related = parser.parseRelatedTags(
        _response({
          'cat': [
            ['feline', 10],
            ['kitty', '7'],
            ['broken'],
            ['', 5],
          ],
        }),
      );

      expect(related.map((it) => it.name), ['feline', 'kitty']);
      expect(related.map((it) => it.postCount), [10, 7]);
    });
  });

  group('E621', () {
    final parser = E621JsonParser();

    test('asks the single tag endpoint and its wiki', () {
      final request = parser.tagInfoRequest(_server, 'cat')!;
      expect(request.infoUrl, 'https://example.com/tags/cat.json');
      expect(request.wikiUrl, 'https://example.com/wiki_pages/cat.json');
      expect(
        request.aliasUrl,
        'https://example.com/tag_aliases.json'
        '?search[antecedent_name]=cat&limit=20',
      );
      expect(request.relatedUrl, isNull);
    });

    test('reads the tag entry, species category and related string', () {
      final res = _response({
        'name': 'cat',
        'post_count': 500,
        'category': 5,
        'related_tags': 'feline 300 kitty 200 odd',
      });

      final info = parser.parseTagInfo('cat', res)!;
      expect(info.name, 'cat');
      expect(info.category, TagCategory.general);
      expect(info.postCount, 500);
      expect(info.related.map((it) => it.name), ['feline', 'kitty']);
      expect(info.related.map((it) => it.postCount), [300, 200]);
    });

    test('accepts the envelope and the legacy count field', () {
      final info = parser.parseTagInfo(
        'cat',
        _response({
          'tag': {'name': 'cat', 'count': 9, 'category': 7},
        }),
      )!;

      expect(info.postCount, 9);
      expect(info.category, TagCategory.meta);
    });

    test('leaves an unknown category out', () {
      final info = parser.parseTagInfo(
        'cat',
        _response({'name': 'cat', 'category': 6}),
      )!;
      expect(info.category, isNull);
    });

    test('reads a bare alias array', () {
      expect(
        parser.parseTagAliases(
          _response([
            {'status': 'active', 'consequent_name': 'domestic_cat'},
          ]),
        ),
        ['domestic_cat'],
      );
    });
  });

  group('Gelbooru', () {
    final parser = GelbooruJsonParser();

    test('asks for metadata only and carries the JSON flag it was given', () {
      final request = parser.tagInfoRequest(_gelbooru, 'cat')!;
      expect(
        request.infoUrl,
        'https://gelbooru.test/index.php?page=dapi&s=tag&q=index'
        '&name=cat&limit=1&json=1',
      );
      expect(request.wikiUrl, isNull);
      expect(request.relatedUrl, isNull);
      expect(request.aliasUrl, isNull);

      final plain = parser.tagInfoRequest(
        _gelbooru.copyWith(searchUrl: 'index.php?page=dapi&s=post'),
        'cat',
      )!;
      expect(plain.infoUrl, isNot(contains('json=1')));
    });

    test('reads both the JSON envelope and the XML DAPI shape', () {
      final json = parser.parseTagInfo(
        'cat',
        _response({
          '@attributes': {'count': 1},
          'tag': [
            {'name': 'cat', 'count': 12, 'type': 0},
          ],
        }),
      )!;
      expect(json.name, 'cat');
      expect(json.category, TagCategory.general);
      expect(json.postCount, 12);

      final xml = parser.parseTagInfo(
        'cat',
        _response(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<tags count="1"><tag name="cat" count="12" type="4"/></tags>',
        ),
      )!;
      expect(xml.name, 'cat');
      expect(xml.category, TagCategory.character);
      expect(xml.postCount, 12);

      final empty = parser.parseTagInfo(
        'cat',
        _response('<?xml version="1.0" encoding="UTF-8"?><tags count="0"/>'),
      )!;
      expect(empty.hasDetails, isFalse);

      expect(parser.parseTagInfo('cat', _response('nope')), isNull);
    });

    test('recognises the DAPI post endpoint and nothing else', () {
      expect(parser.matchesSearchUrl(_gelbooru.searchUrl), isTrue);
      expect(parser.matchesSearchUrl(_danbooru.searchUrl), isFalse);
    });
  });

  group('DText', () {
    test('strips the markup a wiki body carries', () {
      final summary = dtextSummary(
        'thumb #123\n'
        'h4. Breeds\n'
        '* [[abyssinian_cat|Abyssinian]] is a breed.\n'
        'A "cat":https://example.com is [b]small[/b].\n'
        '\n'
        '\n'
        'More {{tag}}.',
      );

      expect(summary, isNot(contains('thumb')));
      expect(summary, isNot(contains('h4.')));
      expect(summary, isNot(contains('[[')));
      expect(summary, isNot(contains('[b]')));
      expect(summary, contains('Abyssinian is a breed.'));
      expect(summary, contains('A cat is small.'));
      expect(summary, contains('More tag.'));
    });

    test('cuts at a word boundary and marks the cut', () {
      final summary = dtextSummary('word ' * 200, maxLength: 50);

      expect(summary.endsWith('…'), isTrue);
      expect(summary.length, lessThanOrEqualTo(51));
      expect(summary, isNot(contains('  ')));
    });
  });

  group('BooruRepo', () {
    test(
      'resolves a preset engine from its post URL and merges the parts',
      () async {
        final adapter = _TagAdapter({
          '/tags.json': const _Reply([
            {'name': 'cat', 'post_count': 42, 'category': 5},
          ]),
          '/wiki_pages/cat.json': const _Reply({
            'body': 'A [b]cat[/b] is a small feline.',
          }),
          '/related_tag.json': const _Reply({
            'related_tags': [
              {
                'tag': {'name': 'feline', 'post_count': 10},
              },
            ],
          }),
          '/tag_aliases.json': const _Reply([
            {'status': 'active', 'consequent_name': 'kitty'},
          ]),
        });

        final info = await _repo(_danbooru, adapter).getTagInfo('cat');

        expect(info.name, 'cat');
        expect(info.category, TagCategory.meta);
        expect(info.postCount, 42);
        expect(info.wiki, 'A cat is a small feline.');
        expect(info.aliases, ['kitty']);
        expect(info.related.map((it) => it.name), ['feline']);
        expect(adapter.requests, hasLength(4));
      },
    );

    test('says unsupported for an engine without a tag endpoint', () async {
      const rails = Server(
        id: 'Rails',
        homepage: 'https://rails.test',
        searchUrl:
            'api/v1/json/search/images?q={tags}&per_page={post-limit}&page={page-num}',
      );
      final adapter = _TagAdapter({});

      await expectLater(
        _repo(rails, adapter).getTagInfo('cat'),
        throwsA(BooruError.tagInfoUnsupported),
      );
      expect(adapter.requests, isEmpty);
    });

    test('keeps the metadata when an optional part fails', () async {
      final adapter = _TagAdapter({
        '/tags.json': const _Reply([
          {'name': 'cat', 'post_count': 42, 'category': 5},
        ]),
        '/wiki_pages/cat.json': const _Reply('broken', status: 500),
        '/related_tag.json': const _Reply({
          'related_tags': [
            {
              'tag': {'name': 'feline', 'post_count': 10},
            },
          ],
        }),
        '/tag_aliases.json': const _Reply([
          {'status': 'active', 'consequent_name': 'kitty'},
        ]),
      });

      final info = await _repo(_danbooru, adapter).getTagInfo('cat');

      expect(info.postCount, 42);
      expect(info.wiki, isEmpty);
      expect(info.aliases, ['kitty']);
      expect(info.related.map((it) => it.name), ['feline']);
    });

    test('reports an unreadable primary answer', () async {
      final adapter = _TagAdapter({'/tags.json': const _Reply('nope')});

      await expectLater(
        _repo(_danbooru, adapter).getTagInfo('cat'),
        throwsA(BooruError.unparsable),
      );
    });

    test('sends the credentials the server already has', () async {
      final adapter = _TagAdapter({
        's=tag': const _Reply({
          'tag': [
            {'name': 'cat', 'count': 1, 'type': 0},
          ],
        }),
      });

      await _repo(_gelbooru, adapter).getTagInfo('cat');

      expect(adapter.requests, hasLength(1));
      final url = adapter.requests.single.uri.toString();
      expect(url, contains('page=dapi&s=tag'));
      expect(url, contains('user_id=user'));
      expect(url, contains('api_key=secret%20key'));
      expect(adapter.requests.single.headers['Authorization'], isNull);
    });
  });
}
