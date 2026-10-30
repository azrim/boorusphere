import 'dart:io';

import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/web_clearance/web_clearance_repo.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/utils/http/cookies.dart';
import 'package:dio/dio.dart';

class HeadersInterceptor extends Interceptor {
  HeadersInterceptor(this.envRepo, this.clearance);

  final EnvRepo envRepo;
  final WebClearanceRepo clearance;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final defaults = HeadersFactory.builder()
        .setReferer(options.path)
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
      final cookies = mergeCookieHeaders(
        options.headers[HttpHeaders.cookieHeader]?.toString(),
        session.cookies,
      );
      if (cookies.isNotEmpty) {
        options.headers[HttpHeaders.cookieHeader] = cookies;
      }
    }
    super.onRequest(options, handler);
  }
}
