import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:dio/dio.dart';

/// The longest body that can still be an authentication notice.
///
/// The engines this covers answer with one short line, in XML or in plain text.
/// Anything larger is a page — a challenge, an error template, a real result —
/// and words inside it mean nothing about the credentials.
const _kMaxAuthNoticeBody = 512;

/// Whether [error] means the server would answer if the account were filled in.
bool isAuthRequired(Object? error) {
  if (error == BooruError.authRequired) return true;
  if (error is! DioException) return false;
  return error.response?.statusCode == 401;
}

/// Whether [body] is an engine's own "no credentials" line rather than a result.
///
/// Rule34's API host answers every `dapi` request without a key as **HTTP 200**
/// with `<error>Missing authentication. Go to api.rule34.xxx for more
/// information`, and the same text as a bare string for the JSON dialect. A
/// status-code check cannot see it and no parser reads it, so it used to reach
/// the reader as "cannot read the response" — the site blamed for a missing
/// API key.
bool isAuthFailureBody(String body) {
  final notice = body.trim();
  if (notice.isEmpty || notice.length > _kMaxAuthNoticeBody) return false;
  return notice.toLowerCase().contains('missing authentication');
}

/// The same reading of a decoded response body.
///
/// The HTTP layer hands over text, bytes or an already-decoded JSON value
/// depending on the engine, and only the text forms can carry the notice.
bool isAuthFailurePayload(Object? data) => switch (data) {
  final String body => isAuthFailureBody(body),
  final List<int> bytes when bytes.length <= _kMaxAuthNoticeBody =>
    isAuthFailureBody(utf8.decode(bytes, allowMalformed: true)),
  _ => false,
};
