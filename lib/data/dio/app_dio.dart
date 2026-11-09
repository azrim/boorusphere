import 'package:boorusphere/data/dio/headers_interceptor.dart';
import 'package:boorusphere/data/dio/host_rate_limiter.dart';
import 'package:boorusphere/data/repository/web_clearance/web_clearance_repo.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/utils/http/cloudflare.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';

/// App HTTP client: the platform client plus the cookie jar, the default
/// headers and the retry policy.
///
/// Extends [DioForNative] rather than `DioMixin` alone: [Dio.download] is
/// implemented by the concrete class, and a bare mixin answers it with
/// `UnimplementedError`, which is what the batch download hit.
class AppDio extends DioForNative {
  AppDio({
    required CookieJar cookieJar,
    required EnvRepo envRepo,
    required WebClearanceRepo clearance,
    List<Duration>? retryDelays,
  }) {
    options = BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      // Redirects are resolved by dart:io, which re-sends a request header
      // only when the target is the same origin (RFC 6454); authorization and
      // cookie headers are dropped otherwise, and a redirect never re-adds the
      // original query string. A 3xx is not a failure: canonical http→https
      // and 301s are common, and reporting them as HTTP errors leaves whole
      // servers unreadable.
      followRedirects: true,
    );
    httpClientAdapter = IOHttpClientAdapter();
    final delays =
        retryDelays ??
        List.generate(5, (index) {
          return Duration(milliseconds: 400 + (100 * (index + 1)));
        });

    interceptors
      ..add(ClearanceCookieResetInterceptor())
      ..add(CookieManager(cookieJar))
      ..add(HeadersInterceptor(envRepo, clearance))
      ..add(
        // A burst of pages and suggestions is what gets an IP blocked. The
        // limiter queues the requests per host and also carries the cooldown a
        // 429 asked for into the one retry.
        HttpEtiquetteInterceptor(dio: this, limiter: HostRateLimiter()),
      )
      ..add(
        RetryInterceptor(
          dio: this,
          retries: delays.length,
          retryDelays: delays,
          // A 429 is the server asking us to back off, not a transient
          // failure. HttpEtiquetteInterceptor already spent the one retry a
          // stated Retry-After allows; a second one here would multiply the
          // pressure the server complained about. A 503 Cloudflare challenge
          // requires the browser flow and will never resolve on API retries.
          retryEvaluator: (error, attempt) {
            if (error.response?.statusCode == 429) return false;
            if (isCloudflareChallenge(error)) return false;
            return RetryInterceptor.defaultRetryEvaluator(error, attempt);
          },
        ),
      );
  }
}
