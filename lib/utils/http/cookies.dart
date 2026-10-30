/// Cookie header handling for requests that carry a session solved in the
/// browser.
///
/// The browser hands back a plain `name=value; name=value` header, while the
/// request may already carry cookies from the shared jar (a login, a
/// preference). The two are merged by name so the browser's value wins and no
/// cookie is sent twice.
library;

String mergeCookieHeaders(String? existing, String? extra) {
  final merged = <String, String>{};

  void addAll(String? header) {
    if (header == null || header.isEmpty) return;
    for (final pair in header.split(';')) {
      final entry = pair.trim();
      if (entry.isEmpty) continue;
      final separator = entry.indexOf('=');
      if (separator <= 0) continue;
      merged[entry.substring(0, separator)] = entry.substring(separator + 1);
    }
  }

  addAll(existing);
  addAll(extra);
  return merged.entries.map((it) => '${it.key}=${it.value}').join('; ');
}
