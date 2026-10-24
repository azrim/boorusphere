import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:xml/xml.dart';

/// Reads one booru XML entry into a flat map.
///
/// Keys come from the element's attributes and from its direct child elements,
/// which is what lets one reader serve both the attribute style (`<post
/// file_url="…"/>`) and the element style (`<post><file_url>…</file_url></post>`).
/// A child element wins when both carry the same name. Values stay strings, the
/// shape the parsers already read through `deep_pick`.
Map<String, dynamic> xmlEntryToMap(XmlElement element) {
  final entry = <String, dynamic>{
    for (final attribute in element.attributes)
      attribute.name.local: attribute.value,
  };
  for (final child in element.childElements) {
    entry[child.name.local] = child.innerText;
  }
  return entry;
}

/// Collects every [entryTag] element directly under the document root.
///
/// Returns null when [payload] is not readable XML, so a caller can tell an
/// unparsable payload from an empty result set.
List<Map<String, dynamic>>? xmlEntries(Object? payload, String entryTag) {
  if (payload is! String) return null;

  final XmlDocument document;
  try {
    document = XmlDocument.parse(payload);
  } on XmlException {
    return null;
  }

  return document.rootElement.childElements
      .where((it) => it.name.local == entryTag)
      .map(xmlEntryToMap)
      .toList();
}

/// Reads a `<tags>` payload into suggestions, or null when it is not XML.
Set<Suggestion>? xmlSuggestions(Object? payload) {
  final entries = xmlEntries(payload, 'tag');
  if (entries == null) return null;

  final result = <Suggestion>{};
  for (final entry in entries) {
    final tag = pick(entry, 'name').asStringOrNull() ?? '';
    final postCount = pick(entry, 'count').asIntOrNull() ?? 0;
    if (postCount > 0 && tag.isNotEmpty) {
      result.add(Suggestion(BooruUtil.decodeTag(tag), postCount));
    }
  }
  return result;
}
