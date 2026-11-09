import 'dart:convert';
import 'dart:typed_data';

import 'package:boorusphere/data/repository/booru/booru_repo.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';
import 'package:boorusphere/data/repository/booru/parser/autocomplete.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/e621_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/moebooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/safebooru_xml_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _server = Server(id: 'Test', homepage: 'https://example.com');

Response _response(Object? data) =>
    Response(requestOptions: RequestOptions(), data: data);

Map<String, TagCategory?> _categories(Iterable<Suggestion> suggestions) {
  return {for (final it in suggestions) it.name: it.category};
}

void main() {
  test('Danbooru maps the numeric category and keeps the unknown ones out', () {
    final res = _response([
      {'name': 'general_tag', 'post_count': 10, 'category': 0},
      {'name': 'artist_tag', 'post_count': 9, 'category': 1},
      {'name': 'copyright_tag', 'post_count': 8, 'category': 3},
      {'name': 'character_tag', 'post_count': 7, 'category': 4},
      {'name': 'meta_tag', 'post_count': 6, 'category': 5},
      // 2 is unused and 6 is deprecated: neither names a real category.
      {'name': 'unused', 'post_count': 5, 'category': 2},
      {'name': 'deprecated', 'post_count': 4, 'category': 6},
      {'name': 'no_category', 'post_count': 3},
    ]);

    final categories = _categories(
      DanbooruJsonParser().parseSuggestion(_server, res),
    );

    expect(categories, {
      'general_tag': TagCategory.general,
      'artist_tag': TagCategory.artist,
      'copyright_tag': TagCategory.copyright,
      'character_tag': TagCategory.character,
      'meta_tag': TagCategory.meta,
      'unused': null,
      'deprecated': null,
      'no_category': null,
    });
  });

  test('Moebooru reads the category from type', () {
    final res = _response([
      {'name': 'solo', 'count': 10, 'type': 4},
      {'name': 'touhou', 'count': 9, 'type': 3},
      {'name': 'books', 'count': 8, 'type': 0},
    ]);

    final categories = _categories(
      MoebooruJsonParser().parseSuggestion(_server, res),
    );

    expect(categories, {
      'solo': TagCategory.character,
      'touhou': TagCategory.copyright,
      'books': TagCategory.general,
    });
  });

  test('Gelbooru JSON reads the category from type', () {
    final res = _response({
      '@attributes': {'limit': 20, 'offset': 0, 'count': 3},
      'tag': [
        {'name': 'artbook', 'count': 10, 'type': 5},
        {'name': 'melonbooks', 'count': 9, 'type': 3},
        {'name': 'book', 'count': 8, 'type': 0},
      ],
    });

    final categories = _categories(
      GelbooruJsonParser().parseSuggestion(_server, res),
    );

    expect(categories, {
      'artbook': TagCategory.meta,
      'melonbooks': TagCategory.copyright,
      'book': TagCategory.general,
    });
  });

  test('Gelbooru XML reads the category from the type attribute', () {
    final res = _response(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<tags count="2" offset="0">'
      '<tag id="1" name="solo" count="10" type="4"/>'
      '<tag id="2" name="bookshelf" count="5" type="0"/>'
      '</tags>',
    );

    final categories = _categories(
      GelbooruXmlParser().parseSuggestion(_server, res),
    );

    expect(categories, {
      'solo': TagCategory.character,
      'bookshelf': TagCategory.general,
    });
  });

  test('a Safebooru autocomplete entry without type has no category', () {
    final res = _response(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<tags count="1" offset="0">'
      '<tag name="book" count="9"/>'
      '</tags>',
    );

    final categories = _categories(
      SafebooruXmlParser().parseSuggestion(_server, res),
    );

    expect(categories, {'book': null});
  });

  test('Danbooru reads the tag from the completion endpoint it asks now', () {
    // The keys `autocomplete.json` reports, from the engine's own serializer:
    // the name it inserts into the search box is `value`, and a word match
    // carries the word the reader typed as `antecedent`.
    final res = _response([
      {
        'type': 'tag-word',
        'label': 'Land of the Lost',
        'value': 'land_of_the_lost',
        'category': 3,
        'post_count': 312,
        'antecedent': 'land',
      },
      {
        'type': 'tag',
        'label': 'landscape',
        'value': 'landscape',
        'category': 0,
        'post_count': 106694,
      },
      // A completion with no posts behind it is not a suggestion worth making.
      {
        'type': 'tag',
        'label': 'land_point',
        'value': 'land_point',
        'category': 0,
        'post_count': 0,
      },
      // Metatag completions arrive without a count at all.
      {
        'type': 'metatag',
        'label': 'rating:senstive',
        'value': 'rating:senstive',
      },
    ]);

    final parser = DanbooruJsonParser();
    expect(parser.canParseSuggestion(res), isTrue);

    final categories = _categories(parser.parseSuggestion(_server, res));
    expect(categories, {
      'land_of_the_lost': TagCategory.copyright,
      'landscape': TagCategory.general,
    });
  });

  test(
    'Danbooru keeps metatag-led and metatag-only batches away from AutocompleteJsonParser',
    () async {
      final metatagFirst = jsonEncode([
        {
          'type': 'metatag',
          'label': 'rating:general',
          'value': 'rating:general',
        },
        {
          'type': 'tag',
          'label': 'rating_safe 2024',
          'value': 'rating_safe_2024',
          'category': 4,
          'post_count': 42,
        },
        {
          'type': 'tag',
          'label': 'rating_empty',
          'value': 'rating_empty',
          'category': 0,
          'post_count': 0,
        },
      ]);
      final metatagOnly = jsonEncode([
        {'type': 'metatag', 'label': 'id: 100', 'value': 'id:100'},
      ]);

      Future<Set<Suggestion>> dispatch(String payload) {
        final dio = Dio()..httpClientAdapter = _JsonAdapter(payload);
        final repo = BooruRepo(
          parsers: [DanbooruJsonParser(), AutocompleteJsonParser()],
          client: dio,
          server: const Server(
            id: 'Danbooru',
            homepage: 'https://danbooru.test',
            tagSuggestionUrl:
                'autocomplete.json?search[query]={tag-part}&limit={post-limit}',
            suggestionParserId: 'Danbooru.json',
          ),
          serverState: ServerState(),
        );
        return repo.getSuggestion('rat');
      }

      final firstResult = await dispatch(metatagFirst);
      expect(_categories(firstResult), {
        'rating_safe_2024': TagCategory.character,
      });
      expect(firstResult.single.count, 42);

      final onlyResult = await dispatch(metatagOnly);
      expect(onlyResult, isEmpty);
    },
  );

  test('Danbooru still reads the tag table an older entry asks for', () {
    final res = _response([
      {'name': 'book', 'post_count': 105190, 'category': 0},
      // An instance that spells the count differently, and one that sends it
      // as digits instead of a number.
      {'name': 'bookshelf', 'num_posts': 3200, 'category': 0},
      {'name': 'book_series', 'post_count': '41', 'category': 3},
    ]);

    final parser = DanbooruJsonParser();
    expect(parser.canParseSuggestion(res), isTrue);

    final counts = <String, int>{
      for (final it in parser.parseSuggestion(_server, res)) it.name: it.count,
    };
    expect(counts, {'book': 105190, 'bookshelf': 3200, 'book_series': 41});
  });

  test('e621 grades its completions with its own category codes', () {
    // Live payload of `tags/autocomplete.json`, whose codes 5 and 8 are species
    // and lore — the two the Danbooru table would call meta.
    final res = _response([
      {
        'id': 678370,
        'name': 'galliform',
        'post_count': 27582,
        'category': 5,
        'antecedent_name': 'land_fowl',
      },
      {'id': 2318, 'name': 'landscape', 'post_count': 4129, 'category': 0},
      {
        'id': 112,
        'name': 'landon_(fellowwolf)',
        'post_count': 235,
        'category': 4,
      },
    ]);

    final parser = E621JsonParser();
    expect(parser.canParseSuggestion(res), isTrue);

    expect(_categories(parser.parseSuggestion(_server, res)), {
      'galliform': TagCategory.general,
      'landscape': TagCategory.general,
      'landon_(fellowwolf)': TagCategory.character,
    });
  });
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.payload);

  final String payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      payload,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
