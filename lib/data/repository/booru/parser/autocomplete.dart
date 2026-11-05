import 'dart:convert';

import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/utils/extensions/pick.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

class AutocompleteJsonParser extends BooruParser {
  @override
  final id = 'Autocomplete.json';

  @override
  final suggestionQuery = 'autocomplete.php?q={tag-part}';

  @override
  List<BooruParserType> get type => [BooruParserType.suggestion];

  @override
  bool canParsePage(Response res) {
    return false;
  }

  @override
  bool canParseSuggestion(Response res) {
    final data = res.data;

    if (data is Map) {
      return false;
    } else if (data is List && data.isNotEmpty) {
      final first = data.first;
      return first is Map &&
          first.containsKey('label') &&
          first.containsKey('value');
    }
    try {
      final parsed = jsonDecode(data);
      if (parsed is List && parsed.isNotEmpty) {
        final first = parsed.first;
        return first is Map &&
            first.containsKey('label') &&
            first.containsKey('value');
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = res.data is List
        ? List.from(res.data)
        : List.from(jsonDecode(res.data));
    final result = <Suggestion>{};
    for (final Map<String, dynamic> entry in entries) {
      final label = pick(entry, 'label').asStringOrNull() ?? '';
      final tag = pick(entry, 'value').asStringOrNull() ?? '';

      // A count the site sent as its own field wins; the PHP endpoint this
      // parser was written for has none and puts it in the label instead.
      var postCount = pick(entry, 'post_count').asCountOrNull() ?? 0;
      if (postCount == 0) {
        postCount =
            int.tryParse(
              label.split(' ').last.replaceAll('(', '').replaceAll(')', ''),
            ) ??
            0;
      }

      if (tag.isNotEmpty) {
        result.add(Suggestion(BooruUtil.decodeTag(tag), postCount));
      }
    }

    return result;
  }
}
