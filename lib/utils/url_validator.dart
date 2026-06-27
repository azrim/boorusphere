/// Validates that a URL is safe to open externally (http/https only).
bool isSafeUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}
