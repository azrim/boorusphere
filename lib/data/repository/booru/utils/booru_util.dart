import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:html_unescape/html_unescape_small.dart';
import 'package:path/path.dart' as path;

class BooruUtil {
  static String normalizeUrl(Server server, String urlString) {
    final trimmed = urlString.trim();
    if (trimmed.isEmpty) {
      // A post without a sample or a preview is a normal answer, not an error.
      return '';
    }
    try {
      final uri = Uri.parse(trimmed);
      if (uri.hasScheme && uri.hasAuthority && uri.hasAbsolutePath) {
        // valid url, there's nothing to do
        return trimmed;
      }

      final apiAddr = Uri.parse(server.apiAddress);
      // An address without a scheme is served over plain http.
      final scheme = apiAddr.scheme == 'https' ? 'https' : 'http';

      if (!uri.hasScheme) {
        final cpath = path.Context(style: path.Style.url);
        final newAuth = uri.hasAuthority ? uri.authority : apiAddr.authority;
        // The root keeps a relative path from running into the authority.
        final newPath = cpath.join('/', apiAddr.path, uri.path);
        // Assembled as text on purpose: `Uri.https` takes a decoded path and
        // escapes the `%` of every escape the server already applied, so
        // `%20` would reach the network as `%2520` and the file would 404.
        final newQuery = uri.hasQuery ? '?${uri.query}' : '';
        return Uri.parse('$scheme://$newAuth$newPath$newQuery').toString();
      }

      // nothing we can do when there's no authority and path at all
      return '';
    } catch (e) {
      return '';
    }
  }

  /// Reads the entry list an engine keeps under [key] in its response envelope.
  ///
  /// An engine answers a single match with the entry object itself instead of a
  /// one-element list, so both shapes are read the same way. A missing key or a
  /// value that carries no entry yields an empty list; [isEmptyEnvelope] is what
  /// tells that apart from an envelope that has entries.
  static List<Object?> envelopeEntries(Object? data, String key) {
    if (data is! Map) return const [];
    final value = data[key];
    if (value is List) return value;
    if (value is Map) return [value];
    return const [];
  }

  /// Whether [value] is an entry list, or the single entry object an engine
  /// answers with when only one match is left.
  static bool isEntryValue(Object? value) => value is List || value is Map;

  /// Whether [data] is an envelope that carries no entry under [key].
  ///
  /// A key that is missing says nothing about this engine, so the answer is
  /// false and the caller can ask another parser.
  static bool isEmptyEnvelope(Object? data, String key) {
    if (data is! Map || !data.containsKey(key)) return false;
    final value = data[key];
    if (value is List) return value.isEmpty;
    return value is! Map;
  }

  static String decodeTag(String str) {
    try {
      final unescaped = HtmlUnescape().convert(str);
      return Uri.decodeQueryComponent(unescaped);
    } on ArgumentError {
      return str;
    }
  }
}
