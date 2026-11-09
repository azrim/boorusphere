import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:dio/dio.dart';

/// Multi-tenant suffixes under which each third-level subdomain is an
/// independent site and must not share clearance cookies with siblings.
const _multiTenantSuffixes = <String>{
  'appspot.com',
  'booru.org',
  'cloudfront.net',
  'github.io',
  'pages.dev',
  'workers.dev',
};

/// Common registry second-level labels under two-letter country-code TLDs
/// (`example.co.jp`, `example.co.uk`, `example.com.au`).
const _ccTldSecondLevels = <String>{
  'ac',
  'asso',
  'co',
  'com',
  'edu',
  'go',
  'gob',
  'gov',
  'gr',
  'id',
  'lg',
  'mil',
  'my',
  'ne',
  'net',
  'nom',
  'or',
  'org',
  'presse',
  'sch',
  'web',
};

/// Whether [error] is Cloudflare's "Just a moment…" check rather than a plain
/// rejection.
///
/// The check is answered with a 403 or 503 to every client that cannot run its
/// JavaScript, which on this platform is the API client itself. Reporting it as
/// a bare status code reads like the server rejected the query, so the screen
/// can tell the two apart and offer the browser that can answer it.
bool isCloudflareChallenge(Object? error) {
  if (error == BooruError.cloudflareChallenge) return true;
  if (error is! DioException) return false;
  final response = error.response;
  if (response == null) return false;
  final status = response.statusCode;
  // Cloudflare serves the interstitial under either code depending on whether
  // the edge could answer at all.
  if (status != 403 && status != 503) return false;

  final mitigated = response.headers.value('cf-mitigated');
  if (mitigated != null && mitigated.toLowerCase() == 'challenge') return true;

  return _isChallengePage(response.data);
}

/// Whether [other] belongs to the same registrable site as [site] for copying
/// Cloudflare clearance cookies.
bool sameClearanceSite(Uri site, Uri other) {
  if (!site.hasScheme || !other.hasScheme) return false;
  final siteHost = _normalizeHost(site.host);
  final otherHost = _normalizeHost(other.host);
  if (siteHost.isEmpty || otherHost.isEmpty) return false;
  if (siteHost == otherHost) return true;
  if (_isIpLiteral(siteHost) || _isIpLiteral(otherHost)) return false;
  return _registrableDomain(siteHost) == _registrableDomain(otherHost);
}

/// Origins whose cookies belong to the server being cleared: [site], the
/// server's own [apiSite] (when configured), and any [resourceOrigins] on the
/// same registrable site as either.
Set<Uri> candidateClearanceOrigins({
  required Uri site,
  Uri? apiSite,
  Iterable<Uri> resourceOrigins = const [],
}) {
  final validApi =
      apiSite != null && apiSite.hasScheme && apiSite.host.isNotEmpty
      ? apiSite
      : null;
  final result = <Uri>{site, ?validApi};
  for (final origin in resourceOrigins) {
    if (sameClearanceSite(site, origin) ||
        (validApi != null && sameClearanceSite(validApi, origin))) {
      result.add(origin);
    }
  }
  return result;
}

/// Extracts non-empty `cf_clearance` token values from a `Cookie` header.
Set<String> extractClearanceTokens(String? cookieHeader) {
  if (cookieHeader == null || cookieHeader.isEmpty) return const {};
  final tokens = <String>{};
  for (final part in cookieHeader.split(';')) {
    final trimmed = part.trim();
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    final name = trimmed.substring(0, eq).trim();
    final value = trimmed.substring(eq + 1).trim();
    if (name == 'cf_clearance' && value.isNotEmpty) {
      tokens.add(value);
    }
  }
  return tokens;
}

String _normalizeHost(String host) {
  return host.trim().toLowerCase().replaceFirst(RegExp(r'\.+$'), '');
}

bool _isIpLiteral(String host) {
  final unbracketed = host.replaceAll(RegExp(r'^\[|\]$'), '');
  if (unbracketed.contains(':')) return true;
  return InternetAddress.tryParse(unbracketed) != null;
}

String _registrableDomain(String host) {
  final parts = host.split('.');
  if (parts.length <= 2 || parts.any((it) => it.isEmpty)) return host;

  final lastTwo = '${parts[parts.length - 2]}.${parts.last}';
  if (_multiTenantSuffixes.contains(lastTwo)) {
    return parts.sublist(parts.length - 3).join('.');
  }
  if (parts.last.length == 2 &&
      _ccTldSecondLevels.contains(parts[parts.length - 2])) {
    return parts.sublist(parts.length - 3).join('.');
  }
  return lastTwo;
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
