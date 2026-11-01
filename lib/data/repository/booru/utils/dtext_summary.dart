/// Turns a wiki body written in DText into the short plain-text summary a
/// sheet shows.
///
/// DText is the markup Danbooru and E621 wikis are written in. Rendering it
/// would mean shipping a parser for links, quotes, lists and embedded images;
/// a tag sheet only needs the opening prose, so the markup is removed and the
/// text is cut at a word boundary.
String dtextSummary(String body, {int maxLength = 600}) {
  var text = body
      // Embedded thumbnails and images: `thumb #123`, `![alt](url)`.
      .replaceAll(RegExp(r'\b(?:thumb|sample|image)\s+#\d+\b'), '')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      // Service links `{{word}}` keep the word, internal links `[[tag]]` and
      // `[[tag|label]]` keep the label, and `"label":url` keeps the label.
      .replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (match) => match[1] ?? '')
      .replaceAllMapped(
        RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]'),
        (match) => switch (match[2]) {
          final label? when label.trim().isNotEmpty => label,
          _ => match[1] ?? '',
        },
      )
      .replaceAllMapped(RegExp(r'"([^"]+)":\S+'), (match) => match[1] ?? '')
      // Block markup that would otherwise read as punctuation: headings,
      // quotes and bullets.
      .replaceAll(RegExp(r'^\s*h[1-6]\.\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\*\s+', multiLine: true), '')
      // BBCode-style inline tags such as [b]…[/b].
      .replaceAll(
        RegExp(
          r'\[/?(?:b|i|u|s|spoiler|expand|quote|code)\b[^\]]*\]',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
      .trim();

  if (text.length <= maxLength) return text;

  final cut = text.substring(0, maxLength);
  final lastSpace = cut.lastIndexOf(' ');
  // Cutting mid-word is uglier than cutting a few characters early, but a
  // single long word must still end within the cap.
  final end = lastSpace > maxLength * 0.6 ? lastSpace : maxLength;
  text = '${cut.substring(0, end).trimRight()}…';
  return text;
}
