import 'dart:convert';
import 'dart:typed_data';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/parser/autocomplete.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/e621_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/moebooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/philomena_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/safebooru_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/shimmie_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/szurubooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/provider.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_scanner.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../presentation/state/app_version_test.dart';
import '../../utils/dio.dart';
import '../../utils/mocktail.dart';
import '../../utils/riverpod.dart';

void main() async {
  setupLogger(test: true);
  setupMocktailFallbacks();
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer ref = ProviderContainer(
    overrides: [envRepoProvider.overrideWithValue(FakeEnvRepo())],
  );
  late DioAdapterMock adapter = DioAdapterMock(
    ref.read(dioProvider),
    byIntercepting: true,
  );
  late List<BooruParser> parsers = ref.read(booruParsersProvider);

  group('Scanner', () {
    setUpAll(() async {
      ref.setupTestFor(dioProvider);
      ref.setupTestFor(booruParsersProvider);
    });

    tearDownAll(ref.dispose);

    test('Danbooru', () async {
      const host = 'https://danbooru.test';
      adapter
        ..put(
          '$host/posts.json?tags=*&page=1&limit=30',
          FakeResponseBody.fromFixture('danbooru/posts.json', 200),
        )
        ..put(
          '$host/autocomplete.json?search[query]=a&search[type]=tag_query&limit=30',
          FakeResponseBody.fromFixture('danbooru/autocomplete.json', 200),
        )
        ..put(
          '$host/posts/100',
          FakeResponseBody.fromFixture('danbooru/post.html', 200),
        );

      final scanner = BooruScanner(
        parsers: parsers,
        client: ref.read(dioProvider),
      );

      final result = await scanner.scan(const Server(homepage: host));
      final parser = DanbooruJsonParser();

      expect(result.searchUrl, parser.searchQuery);
      expect(result.searchParserId, parser.id);
      expect(result.tagSuggestionUrl, parser.suggestionQuery);
      expect(result.suggestionParserId, parser.id);
      expect(result.postUrl, parser.postUrl);
    });

    test('Gelbooru', () async {
      const host = 'https://gelbooru.test';

      adapter
        ..put(
          '$host/index.php?page=dapi&s=post&q=index&tags=*&pid=1&limit=30&json=1',
          FakeResponseBody.fromFixture('gelbooru/posts.json', 200),
        )
        ..put(
          '$host/index.php?page=dapi&s=tag&q=index&name_pattern=%25a%25&orderby=count&limit=30&json=1',
          FakeResponseBody.fromFixture('gelbooru/tags.json', 200),
        )
        ..put(
          '$host/index.php?page=post&s=view&id=100',
          FakeResponseBody.fromFixture('gelbooru/post.html', 200),
        );

      final scanner = BooruScanner(
        parsers: parsers,
        client: ref.read(dioProvider),
      );

      final result = await scanner.scan(const Server(homepage: host));
      final parserJson = GelbooruJsonParser();
      final parserXml = GelbooruXmlParser();

      expect(result.searchUrl, parserJson.searchQuery);
      expect(result.searchParserId, parserJson.id);
      expect(result.tagSuggestionUrl, parserJson.suggestionQuery);
      expect(result.suggestionParserId, parserJson.id);
      expect(result.postUrl, parserXml.postUrl);
    });

    test('Moebooru', () async {
      const host = 'https://konachan.test';

      adapter
        ..put(
          '$host/post.json?tags=*&page=1&limit=30',
          FakeResponseBody.fromFixture('konachan/posts.json', 200),
        )
        ..put(
          '$host/tag.json?name=*a*&order=count&limit=30',
          FakeResponseBody.fromFixture('konachan/tags.json', 200),
        )
        ..put(
          '$host/post/show/100',
          FakeResponseBody.fromFixture('konachan/post.html', 200),
        );

      final scanner = BooruScanner(
        parsers: parsers,
        client: ref.read(dioProvider),
      );

      final result = await scanner.scan(const Server(homepage: host));
      final parser = MoebooruJsonParser();

      expect(result.searchUrl, parser.searchQuery);
      expect(result.searchParserId, parser.id);
      expect(result.tagSuggestionUrl, parser.suggestionQuery);
      expect(result.suggestionParserId, parser.id);
      expect(result.postUrl, parser.postUrl);
    });

    test('Safebooru', () async {
      const host = 'https://safebooru.test';
      adapter
        ..put(
          '$host/index.php?page=dapi&s=post&q=index&tags=*&pid=1&limit=30',
          FakeResponseBody.fromFixture('safebooru/posts.xml', 200),
        )
        ..put(
          '$host/autocomplete.php?q=a',
          FakeResponseBody.fromFixture('safebooru/tags.json', 200),
        )
        ..put(
          '$host/index.php?page=post&s=view&id=100',
          FakeResponseBody.fromFixture('safebooru/post.html', 200),
        );

      final scanner = BooruScanner(
        parsers: parsers,
        client: ref.read(dioProvider),
      );

      final result = await scanner.scan(const Server(homepage: host));
      final parser = GelbooruXmlParser();
      final resultParser = SafebooruXmlParser();
      final suggestionParser = AutocompleteJsonParser();

      expect(result.searchUrl, parser.searchQuery);
      expect(result.searchParserId, resultParser.id);
      expect(result.tagSuggestionUrl, suggestionParser.suggestionQuery);
      expect(result.suggestionParserId, suggestionParser.id);
      expect(result.postUrl, parser.postUrl);
    });

    test('Philomena', () async {
      const host = 'https://derpibooru.test';
      adapter
        ..put(
          '$host/api/v1/json/search/images?q=*&per_page=30&page=1',
          FakeResponseBody.fromFixture('philomena/posts.json', 200),
        )
        ..put(
          '$host/api/v1/json/search/tags?q=*a*',
          FakeResponseBody.fromFixture('philomena/tags.json', 200),
        )
        ..put(
          '$host/images/100',
          FakeResponseBody.fromFixture('philomena/post.html', 200),
        );

      final scanner = BooruScanner(
        parsers: parsers,
        client: ref.read(dioProvider),
      );

      final result = await scanner.scan(const Server(homepage: host));
      final parser = PhilomenaJsonParser();

      expect(result.searchUrl, parser.searchQuery);
      expect(result.searchParserId, parser.id);
      expect(result.tagSuggestionUrl, parser.suggestionQuery);
      expect(result.suggestionParserId, parser.id);
      expect(result.postUrl, parser.postUrl);
    });

    test(
      'a board behind a bot check gives no engine and no post page',
      () async {
        // Derpibooru and allthefallen were measured answering every path — the
        // API and the post page alike — with 200 and Anubis. The scan used to
        // read that as a working post address, so it reported a board it had
        // never reached as detected and linked every post to a page with no
        // image in it. Nothing is proven here, so nothing is written.
        const host = 'https://anubis.test';
        final scanner = BooruScanner(
          parsers: parsers,
          client: Dio(BaseOptions(validateStatus: (it) => it == 200))
            ..httpClientAdapter = _RecordingAdapter(
              _anubisWall,
              contentType: _htmlContentType,
            ),
        );

        final result = await scanner.scan(const Server(homepage: host));

        expect(result.searchParserId, '');
        expect(result.suggestionParserId, '');
        expect(result.postUrl, '');
        expect(result.homepage, host);
      },
    );

    test(
      'a bot check does not decide where the posts of a known engine live',
      () async {
        // The wall is standing on another engine's post path here, and the board
        // itself has no page at the address the probe asks. A scan that read the
        // 200 as proof wrote that foreign address onto a server whose dialect was
        // already known from its payload — and every post link then went to a
        // page the board does not have. Refusing the gate leaves the dialect to
        // answer, which is the address the reader actually needs.
        const host = 'https://walled.test';
        adapter
          ..put(
            '$host/api/v1/json/search/images?q=*&per_page=30&page=1',
            FakeResponseBody.fromFixture('philomena/posts.json', 200),
          )
          ..put(
            '$host/api/v1/json/search/tags?q=*a*',
            FakeResponseBody.fromFixture('philomena/tags.json', 200),
          )
          ..put(
            '$host/post/view/100',
            ResponseBody.fromString(
              _anubisWall,
              200,
              headers: {
                Headers.contentTypeHeader: [_htmlContentType],
              },
            ),
          );

        final scanner = BooruScanner(
          parsers: parsers,
          client: ref.read(dioProvider),
        );

        final result = await scanner.scan(const Server(homepage: host));
        final parser = PhilomenaJsonParser();

        expect(result.searchParserId, parser.id);
        expect(result.postUrl, parser.postUrl);
        expect(result.postUrl, isNot(ShimmieXmlParser().postUrl));
        expect(result.homepage, host);
      },
    );

    test(
      'a site that answers nothing keeps what the server was given',
      () async {
        // A scan also refreshes a server the user configured by hand, and every
        // probe can fail on the way there. Writing the empty answer would clear
        // the address the user typed — and Server.postUrlOf resolves an empty
        // one to the homepage, with no error for anyone to see.
        const host = 'https://quiet.test';
        final scanner = BooruScanner(
          parsers: parsers,
          client: ref.read(dioProvider),
        );

        final result = await scanner.scan(
          const Server(homepage: host, postUrl: 'post/show/{post-id}'),
        );

        expect(result.searchParserId, '');
        expect(result.postUrl, 'post/show/{post-id}');
        expect(result.homepage, host);
      },
    );

    test('E621', () async {
      const host = 'https://e621.test';
      adapter
        ..put(
          '$host/posts.json?tags=*&page=1&limit=30',
          FakeResponseBody.fromFixture('e621/posts.json', 200),
        )
        ..put(
          '$host/tags/autocomplete.json?search[name_matches]=a',
          FakeResponseBody.fromFixture('e621/autocomplete.json', 200),
        )
        ..put(
          '$host/posts/100',
          FakeResponseBody.fromFixture('e621/post.html', 200),
        );

      final scanner = BooruScanner(
        parsers: parsers,
        client: ref.read(dioProvider),
      );

      final result = await scanner.scan(const Server(homepage: host));
      // The post page and the search template are Danbooru's own shape, which
      // is why the parser ids differ from the one answering suggestions.
      final parser = DanbooruJsonParser();
      final pageParser = E621JsonParser();

      expect(result.searchUrl, parser.searchQuery);
      expect(result.searchParserId, pageParser.id);
      expect(result.tagSuggestionUrl, pageParser.suggestionQuery);
      expect(result.suggestionParserId, pageParser.id);
      expect(result.postUrl, parser.postUrl);
    });

    test('Shimmie', () async {
      const host = 'https://rule34.paheal.test';
      adapter
        ..put(
          '$host/api/danbooru/find_posts?tags=*&limit=30&page=1',
          FakeResponseBody.fromFixture('rule34.paheal/posts-modern.xml', 200),
        )
        ..put(
          '$host/api/internal/autocomplete?s=a',
          FakeResponseBody.fromFixture('rule34.paheal/tags.json', 200),
        )
        ..put(
          '$host/post/view/100',
          FakeResponseBody.fromFixture('rule34.paheal/post.html', 200),
        );

      final scanner = BooruScanner(
        parsers: parsers,
        client: ref.read(dioProvider),
      );

      final result = await scanner.scan(const Server(homepage: host));
      final parser = ShimmieXmlParser();

      expect(result.searchUrl, parser.searchQuery);
      expect(result.searchParserId, parser.id);
      expect(result.tagSuggestionUrl, parser.suggestionQuery);
      expect(result.suggestionParserId, parser.id);
      expect(result.postUrl, parser.postUrl);
    });

    test('Szurubooru', () async {
      const host = 'https://homestuck.test/resources/booru';
      adapter
        ..put(
          '$host/api/posts?offset=3&limit=30&query=*',
          FakeResponseBody.fromFixture('szurubooru/posts.json', 200),
        )
        ..put(
          '$host/api/tags?offset=0&limit=30&query=a*',
          FakeResponseBody.fromFixture('szurubooru/tags.json', 200),
        )
        ..put(
          '$host/post/100',
          FakeResponseBody.fromFixture('szurubooru/post.html', 200),
        );

      final scanner = BooruScanner(
        parsers: parsers,
        client: ref.read(dioProvider),
      );

      final result = await scanner.scan(const Server(homepage: host));
      final parser = SzurubooruJsonParser();

      expect(result.searchUrl, parser.searchQuery);
      expect(result.searchParserId, parser.id);
      expect(result.tagSuggestionUrl, parser.suggestionQuery);
      expect(result.suggestionParserId, parser.id);
      expect(result.postUrl, parser.postUrl);
    });
  });

  group('probe credentials', () {
    test('an engine that reads a header is probed with that header', () async {
      // The scan decides whether a server has an engine at all, so a probe
      // that spells the credentials in a form the host never reads reports a
      // working private instance as an unknown site.
      const host = 'https://szuru.test';
      final recording = _RecordingAdapter(
        '{"results":[{"id":1,"contentUrl":"https://szuru.test/get/1.png",'
        '"names":["cat"],"usages":5}],"total":1}',
      );
      final scanner = BooruScanner(
        parsers: [SzurubooruJsonParser()],
        client: Dio(BaseOptions(validateStatus: (it) => it == 200))
          ..httpClientAdapter = recording,
      );

      final result = await scanner.scan(
        const Server(homepage: host, login: 'user', apiKey: 'secret key'),
      );

      expect(result.searchParserId, 'Szurubooru.json');
      expect(result.suggestionParserId, 'Szurubooru.json');
      expect(recording.requests, hasLength(3));
      for (final request in recording.requests) {
        expect(
          request.headers['Authorization'],
          'Token ${base64Encode(utf8.encode('user:secret key'))}',
          reason: '${request.uri} was asked without the pair it reads',
        );
        expect(request.uri.toString(), isNot(contains('api_key')));
        expect(request.uri.toString(), isNot(contains('user_id')));
      }
    });
  });
}

/// Answers every request with one body and keeps what was asked.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.body, {this.contentType = Headers.jsonContentType});

  final String body;
  final String contentType;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Dio names its own content types and this is not one of them.
const _htmlContentType = 'text/html';

/// What an Anubis gate hands out for every path it is asked about — the API
/// endpoint and the page holding the post alike. Measured shape from
/// derpibooru.org, 2026-11-05: status 200, and HTML where JSON was asked for.
const _anubisWall = '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <title>Making sure you're not a bot!</title>
    <script src="/.within.website/x/cmd/anubis/static/js/app.min.js"></script>
  </head>
  <body>
    <h1>Making sure you&#39;re not a bot!</h1>
    <p>Request ID: 7f3c1a2b &middot; 100</p>
  </body>
</html>
''';
