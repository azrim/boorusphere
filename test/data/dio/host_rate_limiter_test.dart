import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:boorusphere/data/dio/host_rate_limiter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clock a test can move by waiting; the limiter is the only thing that
/// makes time pass.
class _FakeTime {
  DateTime now = DateTime(2026, 1, 1);

  Future<void> delay(Duration duration) async {
    now = now.add(duration);
  }
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.statuses, {this.retryAfter});

  /// Status codes answered in order; the last one repeats.
  final List<int> statuses;
  final String? retryAfter;
  final requests = <RequestOptions>[];
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final status = statuses[calls.clamp(0, statuses.length - 1)];
    calls++;
    return ResponseBody.fromString(
      jsonEncode({'status': status}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (retryAfter != null) 'retry-after': [retryAfter!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('HostRateLimiter', () {
    test(
      'queues requests beyond the window instead of dropping them',
      () async {
        final time = _FakeTime();
        final limiter = HostRateLimiter(
          maxRequests: 2,
          window: const Duration(seconds: 1),
          clock: () => time.now,
          delay: time.delay,
        );
        final order = <int>[];

        await Future.wait([
          for (var i = 0; i < 3; i++)
            limiter.acquire('a.test').then((_) => order.add(i)),
        ]);

        expect(order, [0, 1, 2]);
        // The third slot only opened after the first grant left the window.
        expect(time.now, DateTime(2026, 1, 1).add(const Duration(seconds: 1)));
      },
    );

    test('one host filling its window does not hold another', () async {
      final time = _FakeTime();
      final limiter = HostRateLimiter(
        maxRequests: 1,
        window: const Duration(seconds: 1),
        clock: () => time.now,
        delay: time.delay,
      );

      await limiter.acquire('a.test');
      await limiter.acquire('b.test');

      expect(time.now, DateTime(2026, 1, 1));
    });

    test('a penalty holds the host until the cooldown ends', () async {
      final time = _FakeTime();
      final limiter = HostRateLimiter(clock: () => time.now, delay: time.delay);
      final start = time.now;

      limiter.penalize('a.test', const Duration(seconds: 5));
      await limiter.acquire('a.test');

      expect(time.now.difference(start), const Duration(seconds: 5));
    });
  });

  group('parseRetryAfter', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    test('reads a number of seconds', () {
      expect(parseRetryAfter('3', now), const Duration(seconds: 3));
      expect(parseRetryAfter(' 12 ', now), const Duration(seconds: 12));
    });

    test('reads an HTTP date', () {
      final at = now.add(const Duration(seconds: 45));
      expect(
        parseRetryAfter(HttpDate.format(at), now),
        const Duration(seconds: 45),
      );
    });

    test('a past date means no wait at all', () {
      final at = now.subtract(const Duration(minutes: 1));
      expect(parseRetryAfter(HttpDate.format(at), now), Duration.zero);
    });

    test('a negative number means no wait at all', () {
      expect(parseRetryAfter('-4', now), Duration.zero);
    });

    test('an absent or unreadable value has no cooldown', () {
      expect(parseRetryAfter(null, now), isNull);
      expect(parseRetryAfter('', now), isNull);
      expect(parseRetryAfter('soon', now), isNull);
    });
  });

  group('HttpEtiquetteInterceptor', () {
    Dio client(_QueueAdapter adapter) {
      final dio = Dio(BaseOptions(validateStatus: (it) => it == 200));
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(
        HttpEtiquetteInterceptor(dio: dio, limiter: HostRateLimiter()),
      );
      return dio;
    }

    test('retries a 429 once after the stated cooldown', () async {
      final adapter = _QueueAdapter([429, 200], retryAfter: '0');
      final dio = client(adapter);

      final res = await dio.get<String>('https://a.test/posts.json');

      expect(res.statusCode, 200);
      expect(adapter.calls, 2);
    });

    test('a second 429 reaches the caller instead of looping', () async {
      final adapter = _QueueAdapter([429], retryAfter: '0');
      final dio = client(adapter);

      await expectLater(
        dio.get<String>('https://a.test/posts.json'),
        throwsA(
          isA<DioException>().having(
            (it) => it.response?.statusCode,
            'status',
            429,
          ),
        ),
      );
      expect(adapter.calls, 2);
    });

    test('without Retry-After the 429 is not retried', () async {
      final adapter = _QueueAdapter([429]);
      final dio = client(adapter);

      await expectLater(
        dio.get<String>('https://a.test/posts.json'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.calls, 1);
    });
  });
}
