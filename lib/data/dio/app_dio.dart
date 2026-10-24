import 'package:boorusphere/data/dio/headers_interceptor.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';

class AppDio with DioMixin implements Dio {
  AppDio({required CookieJar cookieJar, required EnvRepo envRepo}) {
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
    final retryDelays = List.generate(5, (index) {
      return Duration(milliseconds: 400 + (100 * (index + 1)));
    });

    interceptors
      ..add(CookieManager(cookieJar))
      ..add(HeadersInterceptor(envRepo))
      ..add(
        RetryInterceptor(
          dio: this,
          retries: retryDelays.length,
          retryDelays: retryDelays,
          // A 429 is the server asking us to back off, not a transient
          // failure: retrying it multiplies the pressure it just complained
          // about. It reaches the caller immediately, which is also what
          // honoring Retry-After means when no retry is attempted.
          retryEvaluator: (error, attempt) {
            if (error.response?.statusCode == 429) return false;
            return RetryInterceptor.defaultRetryEvaluator(error, attempt);
          },
        ),
      );
  }
}
