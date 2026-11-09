import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_auth.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/utils/http/auth_error.dart';
import 'package:boorusphere/utils/http/cloudflare.dart';
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

  /// Whether the credentials have to travel in the URL for [parser].
  bool _credentialsInQuery(BooruParser parser) =>
      BooruAuth.travelsInQuery(parser, server);

  /// The parser's own headers plus the account credentials it accepts as a
  /// header.
  Map<String, String> _headersFor(BooruParser parser) =>
      BooruAuth.headers(parser, server);

  /// The parser whose account contract signs this request.
  ///
  /// A configured parser names the engine the entry was set up for, and that
  /// contract governs. An entry that names none — a preset carrying an empty
  /// id, a board added from a bare URL, or one whose id no longer names a
  /// registered parser — still has a post endpoint, and the engine answering
  /// it may read the account from a header the query form never produces. The
  /// search URL is matched against the dialect of each parser that does read a
  /// header, the same way the tag sheet picks its endpoint; when none matches,
  /// the request is signed the way an unknown engine always has been, in the
  /// query.
  BooruParser _authParser(BooruParser configured) {
    if (configured.id.isNotEmpty) return configured;
    for (final parser in parsers) {
      if (parser.authStyle == BooruAuthStyle.query) continue;
      if (parser.matchesSearchUrl(server.searchUrl)) return parser;
    }
    return configured;
  }

  Future<Response> _request(String url, BooruParser parser) async {
    final res = await client.get<List<int>>(
      url,
      options: Options(
        validateStatus: (it) => it == 200,
        responseType: ResponseType.bytes,
        headers: _headersFor(parser),
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

    // Some engines refuse to answer without credentials while still reporting
    // success. There is no status code to read in that case, and the body is
    // the only sign the complaint is about the account rather than the query —
    // so it is settled here, before any parser gets to call it unreadable.
    if (isAuthFailurePayload(data)) throw BooruError.authRequired;

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

      final auth = _authParser(parser);
      final suggestionUrl = server.suggestionUrlsOf(
        word,
        includeCredentials: _credentialsInQuery(auth),
      );
      _log.v(
        'getSuggestion(${server.name}): URL = ${suggestionUrl.split('?').first}',
      );
      final res = await _request(suggestionUrl, auth);
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
      if (isCloudflareChallenge(e)) throw BooruError.cloudflareChallenge;
      if (isAuthRequired(e)) throw BooruError.authRequired;
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

      final auth = _authParser(parser);
      final searchUrl = server.searchUrlOf(
        option,
        page: index,
        includeCredentials: _credentialsInQuery(auth),
      );
      final res = await _request(searchUrl, auth);

      if (parser.canParsePage(res)) {
        _log.i('getPage(${server.name}): using ${parser.id}_parser');
        return parser.parsePage(server, res);
      }

      parser = parsers.firstWhere(
        (it) => it.canParsePage(res),
        orElse: NoParser.new,
      );

      if (parser.id.isNotEmpty) {
        _log.i(
          'getPage(${server.name}): parser resolved, now using ${parser.id}_parser',
        );
        return parser.parsePage(server, res);
      }

      // No parser recognised the payload. An empty result is still a valid
      // answer; anything else means the server sent something we cannot read
      // (interstitial page, proxy error, changed API), which must not be
      // reported to the user as "no results". Only the parsers know what an
      // empty result looks like for the engine that answered.
      if (_isEmptyPayload(res)) return const ParsedPage.empty();
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
      if (isCloudflareChallenge(e)) throw BooruError.cloudflareChallenge;
      if (isAuthRequired(e)) throw BooruError.authRequired;
      rethrow;
    }
  }

  /// Whether [res] is an empty result rather than a payload no parser reads.
  ///
  /// The shape of an empty result belongs to the engine, so the parsers answer
  /// it: a bare empty string and an empty list are empty by construction, and
  /// everything else is offered to every registered parser.
  bool _isEmptyPayload(Response res) {
    final data = res.data;
    if (data is String && data.trim().isEmpty) return true;
    if (data is List) return data.isEmpty;
    return parsers.any((it) => it.isEmptyPayload(res));
  }

  /// The parser that answers tag descriptions for this server.
  ///
  /// A configured search parser decides when it carries the capability. The
  /// built-in presets carry no parser id, so their post endpoint is matched
  /// against the dialect each capable parser recognises.
  BooruParser? _tagInfoParser() {
    final configured = parsers.firstWhere(
      (it) => it.id == server.searchParserId,
      orElse: NoParser.new,
    );
    if (configured.canServeTagInfo) return configured;

    for (final parser in parsers) {
      if (parser.canServeTagInfo && parser.matchesSearchUrl(server.searchUrl)) {
        return parser;
      }
    }
    return null;
  }

  String _withCredentials(BooruParser parser, String url) =>
      _credentialsInQuery(parser) ? server.appendCredentials(url) : url;

  /// Reads one optional part of a tag description.
  ///
  /// A wiki the engine hides from anonymous clients, or a related-tag endpoint
  /// that times out, must not take the metadata that did arrive with it.
  Future<T> _readOptional<T>(
    BooruParser parser,
    String url,
    T Function(Response) read,
    T fallback,
  ) async {
    try {
      final res = await _request(_withCredentials(parser, url), parser);
      return read(res);
    } catch (e) {
      _log.d('getTagInfo(${server.name}): optional part unavailable: $e');
      return fallback;
    }
  }

  @override
  Future<TagInfo> getTagInfo(String tag) async {
    final query = tag.trim();
    if (query.isEmpty) return const TagInfo(name: '');

    final parser = _tagInfoParser();
    final request = parser?.tagInfoRequest(server, query);
    if (parser == null || request == null) {
      throw BooruError.tagInfoUnsupported;
    }

    try {
      final res = await _request(
        _withCredentials(parser, request.infoUrl),
        parser,
      );
      final info = parser.parseTagInfo(query, res);
      if (info == null) throw BooruError.unparsable;

      // The parts are independent, so they are asked for together: a reader
      // waiting for a sheet should wait one round trip, not four.
      final wikiUrl = request.wikiUrl;
      final aliasUrl = request.aliasUrl;
      final relatedUrl = request.relatedUrl;
      final parts = await Future.wait<Object>([
        if (wikiUrl != null && info.wiki.isEmpty)
          _readOptional(parser, wikiUrl, parser.parseTagWiki, '')
        else
          Future.value(info.wiki),
        if (aliasUrl != null && info.aliases.isEmpty)
          _readOptional(
            parser,
            aliasUrl,
            parser.parseTagAliases,
            const <String>[],
          )
        else
          Future.value(info.aliases),
        if (relatedUrl != null && info.related.isEmpty)
          _readOptional(
            parser,
            relatedUrl,
            parser.parseRelatedTags,
            const <TagInfoRelated>[],
          )
        else
          Future.value(info.related),
      ]);

      return TagInfo(
        name: info.name,
        category: info.category,
        postCount: info.postCount,
        wiki: parts[0] as String,
        aliases: parts[1] as List<String>,
        related: parts[2] as List<TagInfoRelated>,
      );
    } on DioException catch (e) {
      if (isCloudflareChallenge(e)) throw BooruError.cloudflareChallenge;
      if (isAuthRequired(e)) throw BooruError.authRequired;
      rethrow;
    }
  }
}
