import 'dart:typed_data';

import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_scanner.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeParser extends BooruParser {
  const _FakeParser();

  @override
  String get id => 'Fake.json';

  @override
  Iterable<BooruParserType> get type => BooruParserType.values;

  @override
  String get searchQuery => 'posts.json?tags={tags}&limit={post-limit}';

  @override
  String get suggestionQuery =>
      'tags.json?name_pattern=%{tag-part}%&limit={post-limit}';

  @override
  String get postUrl => 'posts/{post-id}';

  @override
  bool canParsePage(Response res) => true;

  @override
  bool canParseSuggestion(Response res) => true;
}

void main() {
  group('Server.appendCredentials', () {
    test('copies a literal percent in the query instead of decoding it', () {
      const server = Server(login: 'u1', apiKey: 'k1');
      expect(
        server.appendCredentials('https://a.test/x?name_pattern=%cat%'),
        'https://a.test/x?name_pattern=%cat%&user_id=u1&api_key=k1',
      );
    });

    test('encodes each value on its own', () {
      const server = Server(login: 'user id', apiKey: 'key&value');
      expect(
        server.appendCredentials('https://a.test/x?q=1'),
        'https://a.test/x?q=1&user_id=user%20id&api_key=key%26value',
      );
    });

    test('leaves the url alone without credentials', () {
      const server = Server();
      expect(
        server.appendCredentials('https://a.test/x?q=1'),
        'https://a.test/x?q=1',
      );
    });
  });

  group('Server.suggestionUrlsOf', () {
    test('appends credentials to a percent-wrapped template', () {
      const server = Server(
        homepage: 'https://rule34.test',
        tagSuggestionUrl:
            'index.php?page=dapi&s=tag&name_pattern=%{tag-part}%&limit={post-limit}',
        login: 'u1',
        apiKey: 'k1',
      );

      final url = server.suggestionUrlsOf('cat');
      expect(url, contains('name_pattern=%cat%'));
      expect(url, contains('user_id=u1'));
      expect(url, contains('api_key=k1'));
    });
  });

  group('Server.searchUrlOf', () {
    test('drops the whole rating token on booru-on-rails', () {
      const server = Server(
        homepage: 'https://derpibooru.test',
        searchUrl:
            'api/v1/json/search/images?q={tags}&per_page={post-limit}&page={page-num}',
      );
      const option = PageOption(
        query: 'rating:explicit cat',
        searchRating: BooruRating.explicit,
      );

      final url = server.searchUrlOf(option, page: 0);
      // The engine has no rating filter, and leaving the value behind searched
      // for a tag named "explicit".
      expect(url, contains('q=cat'));
      expect(url, isNot(contains('explicit')));
    });
  });

  group('BooruScanner credentials', () {
    test('probes carry them while the saved query stays a template', () async {
      final adapter = _RecordingAdapter();
      final client = Dio(BaseOptions(followRedirects: true))
        ..httpClientAdapter = adapter;
      final scanner = BooruScanner(
        parsers: const [_FakeParser()],
        client: client,
      );

      final result = await scanner.scan(
        const Server(
          id: 'rule34',
          homepage: 'https://rule34.test',
          login: 'u1',
          apiKey: 'k1',
        ),
      );

      expect(adapter.requests, isNotEmpty);
      for (final request in adapter.requests) {
        // queryParameters would decode the %-wrapped template, so the raw
        // string is what the probe is checked against.
        final uri = request.uri.toString();
        expect(uri, contains('user_id=u1'));
        expect(uri, contains('api_key=k1'));
      }

      // The key must not leak into the stored configuration.
      expect(result.searchUrl, 'posts.json?tags={tags}&limit={post-limit}');
      expect(result.searchUrl, isNot(contains('api_key')));
      expect(result.tagSuggestionUrl, isNot(contains('api_key')));
      expect(result.postUrl, 'posts/{post-id}');
    });
  });
}
