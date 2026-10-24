import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
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
      // Interpolating the payload stringifies the whole response twice; skip it
      // unless the log will actually be written, since this runs per keystroke.
      if (_log.isLoggable(Level.INFO)) {
        final preview = res.data.toString();
        _log.i(
          'getSuggestion(${server.name}): response data type = ${res.data.runtimeType}'
          ' data = ${preview.substring(0, preview.length.clamp(0, 200))}',
        );
      }

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
  Future<ParsedPage> getPage(PageOption option, int index) async {
    try {
      var parser = parsers.firstWhere(
        (x) => x.id == server.searchParserId,
        orElse: NoParser.new,
      );

      final searchUrl = server.searchUrlOf(option, page: index);
      final res = await _request(searchUrl, parser);

      if (parser.canParsePage(res)) {
        _log.i('getPage(${server.name}): using ${parser.id}_parser');
        return _dedupe(parser.parsePage(server, res));
      }

      parser = parsers.firstWhere(
        (it) => it.canParsePage(res),
        orElse: NoParser.new,
      );

      if (parser.id.isNotEmpty) {
        _log.i(
          'getPage(${server.name}): parser resolved, now using ${parser.id}_parser',
        );
        return _dedupe(parser.parsePage(server, res));
      }

      // No parser recognised the payload. An empty result is still a valid
      // answer; anything else means the server sent something we cannot read
      // (interstitial page, proxy error, changed API), which must not be
      // reported to the user as "no results".
      if (_isEmptyPayload(res.data)) return const ParsedPage.empty();
      _log.w('getPage(${server.name}): no parser matched the response');
      throw BooruError.unparsable;
    } on FormatException catch (_) {
      _log.w('getPage(${server.name}): UTF-8 decode error, returning empty');
      return const ParsedPage.empty();
    } on DioException catch (e) {
      if (e.error is FormatException) {
        _log.w(
          'getPage(${server.name}): UTF-8 decode error in Dio, returning empty',
        );
        return const ParsedPage.empty();
      }
      rethrow;
    }
  }

  /// Collapses equal posts, matching the set semantics the page pipeline was
  /// built around. Parsers already de-duplicate by id; this keeps that
  /// guarantee at the repository boundary.
  ParsedPage _dedupe(ParsedPage page) {
    return ParsedPage(
      posts: page.posts.toSet().toList(),
      rawCount: page.rawCount,
    );
  }

  /// Whether [data] is an empty result rather than a payload no parser reads.
  bool _isEmptyPayload(Object? data) {
    if (data is String) {
      final trimmed = data.trim();
      return trimmed.isEmpty || trimmed.contains('<posts');
    }
    if (data is List) return data.isEmpty;
    return false;
  }
}
