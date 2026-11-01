import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:deep_pick/deep_pick.dart';

/// Reads the alias names an engine reports for a tag.
///
/// Danbooru and E621 answer with a bare list; an engine that wraps the list in
/// an envelope is read from the first list it carries. A deleted alias does not
/// describe the tag the reader is looking at, so only active entries count.
List<String> tagAliasNamesFrom(Object? data) {
  List<Object?>? entries;
  if (data is List) {
    entries = data;
  } else if (data is Map) {
    for (final value in data.values) {
      if (value is List) {
        entries = value;
        break;
      }
    }
  }
  if (entries == null) return const [];

  final names = <String>[];
  for (final entry in entries.whereType<Map>()) {
    final status = pick(entry, 'status').asStringOrNull() ?? 'active';
    if (status != 'active') continue;

    final name = BooruUtil.decodeTag(
      pick(entry, 'consequent_name').asStringOrNull() ?? '',
    );
    if (name.isNotEmpty) names.add(name);
  }
  return names.toSet().take(20).toList();
}
