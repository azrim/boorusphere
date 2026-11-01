import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Spaces requests to one host so a burst never turns into a block.
///
/// Requests are queued, never dropped: a caller waits for its slot instead of
/// receiving an error the screen would have to explain. The window slides, so
/// the limit is "at most [maxRequests] in any [window]", which is what most
/// booru edges actually meter.
class HostRateLimiter {
  HostRateLimiter({
    this.maxRequests = 8,
    this.window = const Duration(seconds: 1),
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final int maxRequests;
  final Duration window;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  /// Timestamps of the requests already let through, per host.
  final Map<String, List<DateTime>> _grants = {};

  /// Hosts whose next slot is held back by a 429 and its Retry-After.
  final Map<String, DateTime> _blockedUntil = {};

  /// Serialises the waiters of a host, so two requests waking at the same
  /// moment cannot both take the last slot.
  final Map<String, Future<void>> _tails = {};

  /// Waits until [host] has room for this request, then grants it.
  Future<void> acquire(String host) {
    final previous = _tails[host] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[host] = done.future;

    return previous.then((_) async {
      try {
        while (true) {
          final now = _clock();
          final blockedUntil = _blockedUntil[host];
          if (blockedUntil != null && now.isBefore(blockedUntil)) {
            await _delay(blockedUntil.difference(now));
            continue;
          }

          final grants = _prune(host, now);
          if (grants.length < maxRequests) {
            grants.add(now);
            return;
          }

          // The oldest grant has to leave the window first. The clamp keeps a
          // clock that jumped backwards from asking for a negative delay.
          final wait = grants.first.add(window).difference(now);
          await _delay(wait.isNegative ? Duration.zero : wait);
        }
      } finally {
        done.complete();
      }
    });
  }

  /// Keeps [host] out of the queue for [cooldown], as a 429 asked.
  void penalize(String host, Duration cooldown) {
    if (host.isEmpty) return;
    final until = _clock().add(cooldown);
    final current = _blockedUntil[host];
    if (current == null || until.isAfter(current)) {
      _blockedUntil[host] = until;
    }
  }

  List<DateTime> _prune(String host, DateTime now) {
    final grants = _grants.putIfAbsent(host, () => []);
    grants.removeWhere((it) => now.difference(it) >= window);
    return grants;
  }
}

/// Reads a `Retry-After` header value into a cooldown, or null when the value
/// is missing or unreadable.
///
/// The header carries either a number of seconds or an HTTP date; both forms
/// are in the wild, and a proxy can leave an empty value behind.
Duration? parseRetryAfter(String? value, DateTime now) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  final seconds = int.tryParse(raw);
  if (seconds != null) {
    return seconds <= 0 ? Duration.zero : Duration(seconds: seconds);
  }

  try {
    final at = HttpDate.parse(raw);
    final wait = at.difference(now);
    return wait.isNegative ? Duration.zero : wait;
  } catch (_) {
    return null;
  }
}

/// Applies the per-host limit, and turns a 429 with `Retry-After` into one
/// bounded retry.
///
/// The retry is marked on the request options, so a server that answers 429
/// again reaches the caller as the error it is instead of looping.
class HttpEtiquetteInterceptor extends Interceptor {
  HttpEtiquetteInterceptor({
    required this.dio,
    required this.limiter,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Request-option key that records the one retry already spent.
  static const retryMarker = 'http_etiquette_retry_429';

  /// Longest cooldown a `Retry-After` can impose. A server asking for an hour
  /// would leave the app waiting on a page the reader has already left.
  static const maxRetryAfter = Duration(seconds: 60);

  static const _retryAfterHeader = 'retry-after';

  final Dio dio;
  final HostRateLimiter limiter;
  final DateTime Function() _clock;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final host = options.uri.host;
    if (host.isNotEmpty) await limiter.acquire(host);
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response?.statusCode != 429) {
      handler.next(err);
      return;
    }

    final retryAfter = parseRetryAfter(
      response?.headers.value(_retryAfterHeader),
      _clock(),
    );
    // Without a stated cooldown, retrying is guessing when the server is
    // ready; the caller gets the error and its retry button instead.
    if (retryAfter == null) {
      handler.next(err);
      return;
    }

    final cooldown = retryAfter > maxRetryAfter ? maxRetryAfter : retryAfter;
    limiter.penalize(err.requestOptions.uri.host, cooldown);

    if (err.requestOptions.extra[retryMarker] == true) {
      handler.next(err);
      return;
    }
    err.requestOptions.extra[retryMarker] = true;

    try {
      // Going through the client again is what applies the cooldown: the
      // request interceptor above waits for the host's next slot.
      handler.resolve(await dio.fetch(err.requestOptions));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
