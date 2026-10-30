import 'dart:convert';

import 'package:dio/dio.dart';

/// Whether [error] is Cloudflare's "Just a moment…" check rather than a plain
/// rejection.
///
/// The check is answered with a 403 to every client that cannot run its
/// JavaScript, which on this platform is the API client itself. Reporting it as
/// a bare status code reads like the server rejected the query, so the screen
/// can tell the two apart and offer the browser that can answer it.
bool isCloudflareChallenge(Object? error) {
  if (error is! DioException) return false;
  final response = error.response;
  if (response == null || response.statusCode != 403) return false;

  final mitigated = response.headers.value('cf-mitigated');
  if (mitigated != null && mitigated.toLowerCase() == 'challenge') return true;

  return _isChallengePage(response.data);
}

/// Reads the body for the challenge markers, since a proxy can strip the
/// header while leaving the interstitial in place.
bool _isChallengePage(Object? data) {
  const limit = 64 * 1024;
  final body = switch (data) {
    final String value => value,
    final List<int> value when value.length <= limit => utf8.decode(
      value,
      allowMalformed: true,
    ),
    _ => '',
  };
  if (body.isEmpty) return false;
  return body.contains('cf_chl_opt') || body.contains('Just a moment');
}
