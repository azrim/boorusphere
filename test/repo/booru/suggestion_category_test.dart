import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/moebooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/safebooru_xml_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
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
}
