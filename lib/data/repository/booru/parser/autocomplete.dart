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

  List _decodeList(Object? data) {
    if (data is List) return data;
    if (data is String) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is List) return parsed;
      } catch (_) {}
    }
    return const [];
  }

  @override
  bool canParseSuggestion(Response res) {
    final entries = _decodeList(res.data);
    return entries.any(
      (it) => it is Map && it.containsKey('label') && it.containsKey('value'),
    );
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = _decodeList(res.data);
    final result = <Suggestion>{};
    for (final entry in entries.whereType<Map>()) {
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
