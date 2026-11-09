import 'dart:io';

import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/web_clearance/web_clearance_repo.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/utils/http/cookies.dart';
import 'package:dio/dio.dart';

const _jarCookieSnapshotKey = '_jar_cookie_snapshot';

class _JarCookieSnapshot {
  const _JarCookieSnapshot(this.header);

  final Object? header;
}

/// Restores the pre-clearance `Cookie` header before [CookieManager] inspects a
/// retried [RequestOptions].
///
/// [CookieManager] parses any `Cookie` header that differs from its own prior
/// output with [Cookie.fromSetCookieValue], which rejects browser cookies whose
/// values contain JSON quotes, commas, or spaces. Resetting to the jar snapshot
/// lets [CookieManager] refresh jar cookies cleanly while [HeadersInterceptor]
/// appends the browser clearance afterward.
class ClearanceCookieResetInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final snapshot = options.extra.remove(_jarCookieSnapshotKey);
    if (snapshot is _JarCookieSnapshot) {
      if (snapshot.header == null) {
        options.headers.remove(HttpHeaders.cookieHeader);
      } else {
        options.headers[HttpHeaders.cookieHeader] = snapshot.header;
      }
    }
    super.onRequest(options, handler);
  }
}

class HeadersInterceptor extends Interceptor {
  HeadersInterceptor(this.envRepo, this.clearance);

  final EnvRepo envRepo;
  final WebClearanceRepo clearance;

  static String _defaultReferer(Uri uri) {
    if ((uri.isScheme('http') || uri.isScheme('https')) && uri.hasAuthority) {
      return '${uri.origin}/';
    }
    return uri.path;
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Default Referer carries only the origin, keeping query-string API
    // credentials out of a header that HTTP redirects forward verbatim.
    final defaults = HeadersFactory.builder()
        .setReferer(_defaultReferer(options.uri))
        .setUserAgent(envRepo.appVersion)
        .build();

    // These are defaults for requests that carry none. A caller that sets its
    // own User-Agent or Referer keeps it: the batch download points the
    // Referer at the post page, and the path of the file request would
    // replace it with the file URL a hotlink-protected booru rejects.
    for (final entry in defaults.entries) {
      options.headers.putIfAbsent(entry.key, () => entry.value);
    }

    // A server that challenged the API client was solved in the browser for
    // this host, and Cloudflare ties the clearance to the agent that earned
    // it. Sending that cookie under this app's own User-Agent is challenged
    // again, so the pair travels together.
    final session = clearance.forHost(options.uri.host);
    if (session != null) {
      options.headers[HttpHeaders.userAgentHeader] = session.userAgent;
      final priorCookie = options.headers[HttpHeaders.cookieHeader];
      final cookies = mergeCookieHeaders(
        priorCookie?.toString(),
        session.cookies,
      );
      if (cookies.isNotEmpty) {
        options.extra[_jarCookieSnapshotKey] = _JarCookieSnapshot(priorCookie);
        options.headers[HttpHeaders.cookieHeader] = cookies;
      }
    }
    super.onRequest(options, handler);
  }
}
