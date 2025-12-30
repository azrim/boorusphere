import 'dart:convert';

import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

/// Parser for Gelbooru's autocomplete2 endpoint.
/// Response format: [{"type":"tag","label":"tag name","value":"tag_name","post_count":"12345","category":"tag"}, ...]
class GelbooruAutocompleteParser extends BooruParser {
  @override
  final id = 'Gelbooru.autocomplete';

  @override
  final suggestionQuery =
      'index.php?page=autocomplete2&term={tag-part}&type=tag_query&limit={post-limit}';

  @override
  List<BooruParserType> get type => [
        BooruParserType.suggestion,
      ];

  @override
  bool canParsePage(Response res) {
    return false;
  }

  @override
  bool canParseSuggestion(Response res) {
    final data = res.data;

    // Check if it's a list with label/value/post_count format
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map) {
        return first.containsKey('label') &&
            first.containsKey('value') &&
            first.containsKey('post_count');
      }
    }

    // Try parsing string as JSON
    if (data is String) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is List && parsed.isNotEmpty) {
          final first = parsed.first;
          if (first is Map) {
            return first.containsKey('label') &&
                first.containsKey('value') &&
                first.containsKey('post_count');
          }
        }
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final List entries;
    if (res.data is List) {
      entries = res.data;
    } else if (res.data is String) {
      entries = jsonDecode(res.data);
    } else {
      return {};
    }

    final result = <Suggestion>{};
    for (final entry in entries) {
      if (entry is! Map) continue;

      final tag = pick(entry, 'value').asStringOrNull() ?? '';
      // post_count is a string in the response
      final postCountStr = pick(entry, 'post_count').asStringOrNull() ?? '0';
      final postCount = int.tryParse(postCountStr) ?? 0;

      if (tag.isNotEmpty) {
        result.add(Suggestion(BooruUtil.decodeTag(tag), postCount));
      }
    }

    return result;
  }
}
