import 'package:boorusphere/data/repository/booru/parser/booruonrails_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/safebooru_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/shimmie_xml_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _server = Server(
  id: 'Test',
  homepage: 'https://example.com',
  postUrl: 'post/{post-id}',
);

Response _response(Object? data) =>
    Response(requestOptions: RequestOptions(), data: data);

Map<String, dynamic> _image({int id = 1, List<String> tags = const []}) {
  return {
    'id': id,
    'view_url': 'https://cdn.example.com/$id.jpg',
    'representations': {
      'large': 'https://cdn.example.com/$id-large.jpg',
      'thumb': 'https://cdn.example.com/$id-thumb.jpg',
    },
    'width': 100,
    'height': 100,
    'tags': tags,
  };
}

void main() {
  group('empty XML payloads return empty results instead of throwing', () {
    // The Parker converter (Gelbooru) turns a childless element into `null`, so
    // an empty envelope is expressed as a present-but-empty entry.
    test('Gelbooru XML suggestion', () {
      final res = _response(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<tags count="0" offset="0"><tag></tag></tags>',
      );
      expect(GelbooruXmlParser().parseSuggestion(_server, res), isEmpty);
    });

    test('Safebooru XML suggestion', () {
      final res = _response(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<tags count="0" offset="0"></tags>',
      );
      expect(SafebooruXmlParser().parseSuggestion(_server, res), isEmpty);
    });

    test('Gelbooru XML post', () {
      final res = _response(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<posts count="0" offset="0"><post></post></posts>',
      );
      expect(GelbooruXmlParser().parsePage(_server, res), isEmpty);
    });

    test('Safebooru XML post', () {
      final res = _response(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<posts count="0" offset="0"></posts>',
      );
      expect(SafebooruXmlParser().parsePage(_server, res), isEmpty);
    });

    test('Shimmie XML post', () {
      final res = _response(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<posts count="0" offset="0"></posts>',
      );
      expect(ShimmieXmlParser().parsePage(_server, res), isEmpty);
    });
  });

  group('BooruOnRails rating normalization', () {
    test('falls back to q when no rating tag is present', () {
      final res = _response({
        'images': [
          _image(id: 1, tags: ['artist:foo', 'general']),
        ],
      });
      final posts = BooruOnRailsJsonParser().parsePage(_server, res);
      expect(posts, hasLength(1));
      expect(posts.single.rateValue, 'q');
    });

    test('preserves the explicit rating tag', () {
      final res = _response({
        'images': [
          _image(id: 2, tags: ['explicit', 'artist:foo']),
        ],
      });
      final posts = BooruOnRailsJsonParser().parsePage(_server, res);
      expect(posts.single.rateValue, 'explicit');
    });
  });

  test('engine-level de-dup keeps the first guard-passing entry per id', () {
    final res = _response({
      'images': [
        _image(id: 5, tags: ['safe']),
        _image(id: 5, tags: ['explicit']),
      ],
    });
    final posts = BooruOnRailsJsonParser().parsePage(_server, res);
    expect(posts, hasLength(1));
    expect(posts.single.rateValue, 'safe');
  });
}
