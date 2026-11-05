import 'dart:convert';

import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';

/// The account credentials in the one form [parser]'s engine reads.
///
/// Both callers that ask a booru go through here — the timeline's requests and
/// the scanner's probes — because an engine that reads a header answers nothing
/// to the same pair spelled out in a query string, and a scan that got that
/// wrong reports a working server as having no engine at all.
class BooruAuth {
  const BooruAuth._();

  /// Whether the pair has to travel in the URL for [parser].
  ///
  /// A header engine configured only halfway falls back to the query form: an
  /// API key without the login it belongs to is not a header credential either,
  /// and leaving it out would silently drop the only credentials the user has.
  static bool travelsInQuery(BooruParser parser, Server server) {
    return switch (parser.authStyle) {
      BooruAuthStyle.query => true,
      BooruAuthStyle.basic ||
      BooruAuthStyle.token => server.login.isEmpty || server.apiKey.isEmpty,
    };
  }

  /// The parser's own headers plus the credential header it accepts.
  ///
  /// Never logged: a credential in a log line outlives the session it was
  /// meant for.
  static Map<String, String> headers(BooruParser parser, Server server) {
    final scheme = switch (parser.authStyle) {
      BooruAuthStyle.basic => 'Basic',
      BooruAuthStyle.token => 'Token',
      BooruAuthStyle.query => null,
    };
    if (scheme == null || server.login.isEmpty || server.apiKey.isEmpty) {
      return parser.headers;
    }

    // The pair is encoded, not the token alone: both header engines read one
    // base64 blob of `login:api_key` and split it themselves.
    final pair = base64Encode(utf8.encode('${server.login}:${server.apiKey}'));
    return {...parser.headers, 'Authorization': '$scheme $pair'};
  }
}
