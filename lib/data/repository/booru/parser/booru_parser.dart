import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:dio/dio.dart';

abstract class BooruParser {
  const BooruParser();

  String get id;
  String get postUrl => '';
  String get suggestionQuery => '';
  String get searchQuery => '';
  Map<String, String> get headers => {};

  /// How this engine accepts account credentials. Most only read the query
  /// parameters the app has always sent; an engine that documents HTTP Basic
  /// says so, and the credentials then never enter a URL.
  BooruAuthStyle get authStyle => BooruAuthStyle.query;

  Iterable<BooruParserType> get type;
  bool canParsePage(Response res) => false;

  /// Whether [res] is a well-formed *empty* result for this engine, as opposed
  /// to a payload this parser cannot read.
  ///
  /// Each engine knows how its own empty result is shaped — an envelope without
  /// its entry list, a `<posts>` root without entry content — so the dispatcher
  /// can answer "no results" instead of "unparsable".
  bool isEmptyPayload(Response res) => false;

  ParsedPage parsePage(Server server, Response res) => const ParsedPage.empty();
  bool canParseSuggestion(Response res) => false;
  Iterable<Suggestion> parseSuggestion(Server server, Response res) => [];

  /// Whether this parser can describe an individual tag.
  ///
  /// Only engines whose tag endpoints have been observed are switched on. A
  /// parser that answers false leaves the viewer's tag sheet with a friendly
  /// "not supported" instead of a request that would guess at an endpoint.
  bool get canServeTagInfo => false;

  /// Whether [searchUrl] looks like this engine's post endpoint.
  ///
  /// Used to pick the tag-info dialect for a server that carries no parser id,
  /// such as the built-in presets. An explicit [Server.searchParserId] wins
  /// over this.
  bool matchesSearchUrl(String searchUrl) => false;

  /// The endpoints that describe [tag], or null when the parser cannot serve
  /// tag information.
  TagInfoRequest? tagInfoRequest(Server server, String tag) => null;

  /// Reads the primary tag entry, or null when the payload was not understood.
  ///
  /// An understood payload without an entry yields a [TagInfo] carrying only
  /// the requested name, so the reader can tell "no details" apart from "this
  /// is not the API I expected".
  TagInfo? parseTagInfo(String tag, Response res) => null;

  /// A short plain-text wiki summary, or empty when the payload has none.
  String parseTagWiki(Response res) => '';

  /// Names this tag is aliased to, when the engine exposes an alias endpoint.
  List<String> parseTagAliases(Response res) => const [];

  /// Tags used alongside this tag, when the engine exposes them separately
  /// from the primary entry.
  List<TagInfoRelated> parseRelatedTags(Response res) => const [];
}

enum BooruParserType { search, suggestion }

enum BooruAuthStyle {
  /// `user_id`/`api_key` query parameters, the form every engine here reads.
  query,

  /// An HTTP Basic header. Only engines that document it use this.
  basic,
}

class NoParser extends BooruParser {
  const NoParser();

  @override
  final id = '';

  @override
  List<BooruParserType> get type => [];
}
