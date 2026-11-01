import 'dart:convert';
import 'dart:typed_data';

import 'package:boorusphere/data/repository/booru/booru_repo.dart';
import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_json_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.status = 200, this.headers = const {}});

  final int status;
  final Map<String, List<String>> headers;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '[]',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Server _danbooru({String login = 'user', String apiKey = 'secret key'}) {
  return Server(
    id: 'Danbooru',
    homepage: 'https://danbooru.test',
    searchUrl: 'posts.json?tags={tags}&page={page-num}&limit={post-limit}',
    tagSuggestionUrl:
        'tags.json?search[name_matches]=*{tag-part}*&limit={post-limit}',
    searchParserId: 'Danbooru.json',
    suggestionParserId: 'Danbooru.json',
    login: login,
    apiKey: apiKey,
  );
}

BooruRepo _repo(Server server, HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(validateStatus: (it) => it == 200));
  dio.httpClientAdapter = adapter;
  return BooruRepo(
    parsers: [DanbooruJsonParser(), GelbooruJsonParser()],
    client: dio,
    server: server,
    serverState: ServerState(),
  );
}

String _basic(String login, String apiKey) =>
    'Basic ${base64Encode(utf8.encode('$login:$apiKey'))}';

void main() {
  test(
    'Danbooru sends its credentials as a Basic header, not in the URL',
    () async {
      final adapter = _RecordingAdapter();
      final repo = _repo(_danbooru(), adapter);

      await repo.getPage(const PageOption(limit: 1), 0);
      await repo.getSuggestion('ca');

      expect(adapter.requests, hasLength(2));
      for (final request in adapter.requests) {
        expect(request.headers['Authorization'], _basic('user', 'secret key'));
        expect(request.uri.toString(), isNot(contains('api_key')));
        expect(request.uri.toString(), isNot(contains('user_id')));
      }
    },
  );

  test(
    'a lone API key stays in the query where the engine expects it',
    () async {
      final adapter = _RecordingAdapter();
      final repo = _repo(_danbooru(login: ''), adapter);

      await repo.getPage(const PageOption(limit: 1), 0);

      final request = adapter.requests.single;
      expect(request.headers['Authorization'], isNull);
      expect(request.uri.toString(), contains('api_key=secret%20key'));
    },
  );

  test('an engine without Basic support keeps its query credentials', () async {
    final adapter = _RecordingAdapter();
    final repo = BooruRepo(
      parsers: [GelbooruJsonParser()],
      client: Dio(BaseOptions(validateStatus: (it) => it == 200))
        ..httpClientAdapter = adapter,
      server: const Server(
        id: 'Gelbooru',
        homepage: 'https://gelbooru.test',
        searchUrl: 'index.php?page=dapi&s=post&tags={tags}&limit={post-limit}',
        searchParserId: 'Gelbooru.json',
        login: 'user',
        apiKey: 'secret key',
      ),
      serverState: ServerState(),
    );

    await repo.getPage(const PageOption(limit: 1), 0);

    final request = adapter.requests.single;
    expect(request.headers['Authorization'], isNull);
    expect(request.uri.toString(), contains('user_id=user'));
    expect(request.uri.toString(), contains('api_key=secret%20key'));
  });

  test('a challenge response becomes the error the screen knows', () async {
    final adapter = _RecordingAdapter(
      status: 403,
      headers: {
        'cf-mitigated': ['challenge'],
      },
    );
    final repo = _repo(_danbooru(), adapter);

    await expectLater(
      repo.getPage(const PageOption(limit: 1), 0),
      throwsA(BooruError.cloudflareChallenge),
    );
    await expectLater(
      repo.getSuggestion('ca'),
      throwsA(BooruError.cloudflareChallenge),
    );
  });
}
