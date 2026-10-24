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
///
/// Values are trimmed: pretty-printed payloads indent their text nodes, and a
/// URL that arrives with that padding is not a URL.
Map<String, dynamic> xmlEntryToMap(XmlElement element) {
  final entry = <String, dynamic>{
    for (final attribute in element.attributes)
      attribute.name.local: attribute.value.trim(),
  };
  for (final child in element.childElements) {
    entry[child.name.local] = child.innerText.trim();
  }
  return entry;
}

/// Collects every [entryTag] element directly under the document root.
///
/// Returns null when [payload] is not readable XML, so a caller can tell an
/// unparsable payload from an empty result set.
List<Map<String, dynamic>>? xmlEntries(Object? payload, String entryTag) {
  final document = _documentOf(payload);
  if (document == null) return null;

  return document.rootElement.childElements
      .where((it) => it.name.local == entryTag)
      .map(xmlEntryToMap)
      .toList();
}

/// Whether [payload] is a `<posts>` result set that carries no entry content.
///
/// An empty result set arrives either without an entry element
/// (`<posts count="0"/>`) or with a single childless one (`<post></post>`).
/// A root with any valued child is *not* empty: the payload carries content,
/// even when no reader understands it, and answering "no results" there would
/// end pagination for the whole query. Anything that is not a readable
/// `<posts>` document is also not an empty result set, which leaves such a
/// payload to the unparsable path.
bool xmlIsEmptyResultSet(Object? payload) {
  final document = _documentOf(payload);
  if (document == null) return false;

  final root = document.rootElement;
  if (root.name.local != 'posts') return false;
  return root.childElements.every((it) => xmlEntryToMap(it).isEmpty);
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

/// The last payload read by this library.
///
/// The dispatcher asks every registered parser about the same response when it
/// classifies a payload, and the XML readers are pure, so the parse is kept for
/// the response being inspected instead of being repeated per parser. Only the
/// most recent payload is retained.
_ParsedPayload? _lastPayload;

XmlDocument? _documentOf(Object? payload) {
  if (payload is! String) return null;

  final cached = _lastPayload;
  if (cached != null && identical(cached.payload, payload)) {
    return cached.document;
  }

  XmlDocument? document;
  try {
    document = XmlDocument.parse(payload);
  } on XmlException {
    document = null;
  }
  _lastPayload = _ParsedPayload(payload, document);
  return document;
}

class _ParsedPayload {
  const _ParsedPayload(this.payload, this.document);

  final String payload;
  final XmlDocument? document;
}
