import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

class BooruRepo implements ImageboardRepo {
  BooruRepo({
    required this.parsers,
    required this.client,
    required this.server,
    required this.serverState,
  });

  final Iterable<BooruParser> parsers;
  final Dio client;
  final ServerState serverState;

  final _log = Logger('BooruRepo');

  @override
  final Server server;

  Future<Response> _request(String url, BooruParser parser) async {
    final res = await client.get<List<int>>(
      url,
      options: Options(
        validateStatus: (it) => it == 200,
        responseType: ResponseType.bytes,
        headers: parser.headers,
      ),
    );

    // Manually decode bytes to handle malformed UTF-8
    final bytes = res.data ?? <int>[];
    final decoded = utf8.decode(bytes, allowMalformed: true);

    // Parse JSON if applicable
    dynamic data;
    final trimmed = decoded.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        data = json.decode(decoded);
      } catch (e) {
        _log.w('JSON decode failed: $e');
        data = decoded;
      }
    } else {
      data = decoded;
    }

    return Response(
      requestOptions: res.requestOptions,
      statusCode: res.statusCode,
      statusMessage: res.statusMessage,
      headers: res.headers,
      data: data,
    );
  }

  @override
  Future<Set<Suggestion>> getSuggestion(String word) async {
    try {
      var parser = parsers.firstWhere(
        (x) => x.id == server.suggestionParserId,
        orElse: NoParser.new,
      );

      final suggestionUrl = server.suggestionUrlsOf(word);
      _log.v(
        'getSuggestion(${server.name}): URL = ${suggestionUrl.split('?').first}',
      );
      final res = await _request(suggestionUrl, parser);
      _log.i(
        'getSuggestion(${server.name}): response data type = ${res.data.runtimeType}',
      );
      _log.i(
        'getSuggestion(${server.name}): response data = ${res.data.toString().substring(0, (res.data.toString().length).clamp(0, 200))}',
      );

      if (parser.canParseSuggestion(res)) {
        _log.i('getSuggestion(${server.name}): using ${parser.id}_parser');
        return parser.parseSuggestion(server, res).toSet();
      }

      parser = parsers.firstWhere(
        (it) => it.canParseSuggestion(res),
        orElse: NoParser.new,
      );

      if (parser.id.isNotEmpty) {
        _log.i(
          'getSuggestion(${server.name}): parser resolved, now using ${parser.id}_parser',
        );
      } else {
        _log.w('getSuggestion(${server.name}): no parser found for response');
      }

      return parser.parseSuggestion(server, res).toSet();
    } on FormatException catch (_) {
      // Handle malformed UTF-8 from server - return empty results
      _log.w(
        'getSuggestion(${server.name}): UTF-8 decode error, returning empty',
      );
      return {};
    } on DioException catch (e) {
      // Check if the underlying error is a FormatException
      if (e.error is FormatException) {
        _log.w(
          'getSuggestion(${server.name}): UTF-8 decode error in Dio, returning empty',
        );
        return {};
      }
      rethrow;
    }
  }

  @override
  Future<Set<Post>> getPage(PageOption option, int index) async {
    try {
      var parser = parsers.firstWhere(
        (x) => x.id == server.searchParserId,
        orElse: NoParser.new,
      );

      final searchUrl = server.searchUrlOf(option, page: index);
      final res = await _request(searchUrl, parser);

      if (parser.canParsePage(res)) {
        _log.i('getPage(${server.name}): using ${parser.id}_parser');
        return parser.parsePage(server, res).toSet();
      }

      parser = parsers.firstWhere(
        (it) => it.canParsePage(res),
        orElse: NoParser.new,
      );

      if (parser.id.isNotEmpty) {
        _log.i(
          'getPage(${server.name}): parser resolved, now using ${parser.id}_parser',
        );
      }

      return parser.parsePage(server, res).toSet();
    } on FormatException catch (_) {
      _log.w('getPage(${server.name}): UTF-8 decode error, returning empty');
      return {};
    } on DioException catch (e) {
      if (e.error is FormatException) {
        _log.w(
          'getPage(${server.name}): UTF-8 decode error in Dio, returning empty',
        );
        return {};
      }
      rethrow;
    }
  }
}
