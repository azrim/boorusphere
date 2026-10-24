import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
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
}

enum BooruParserType { search, suggestion }

class NoParser extends BooruParser {
  const NoParser();

  @override
  final id = '';

  @override
  List<BooruParserType> get type => [];
}
