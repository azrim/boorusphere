import 'dart:io';
import 'dart:typed_data';

import 'package:boorusphere/data/dio/app_dio.dart';
import 'package:boorusphere/data/dio/headers_interceptor.dart';
import 'package:boorusphere/data/repository/env/fallback_env_repo.dart';
import 'package:boorusphere/data/repository/web_clearance/web_clearance_repo.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Future<RequestOptions> _send(
  HeadersInterceptor interceptor,
  String url, {
  Map<String, dynamic> headers = const {},
}) async {
  final options = RequestOptions(path: url, headers: {...headers});
  await interceptor.onRequest(options, RequestInterceptorHandler());
  return options;
}

void main() {
  test(
    'a solved host sends the browser agent and its cookie together',
    () async {
      final repo = WebClearanceRepo(null);
      await repo.save(
        host: 'danbooru.donmai.us',
        userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 7)',
        cookies: 'cf_clearance=abc; __cf_bm=def',
      );

      final options = await _send(
        HeadersInterceptor(const FallbackEnvRepo(), repo),
        'https://danbooru.donmai.us/posts.json?tags=an',
      );

      expect(
        options.headers['User-Agent'],
        'Mozilla/5.0 (Linux; Android 14; Pixel 7)',
      );
      expect(options.headers['Cookie'], 'cf_clearance=abc; __cf_bm=def');
    },
  );

  test('the image host of a solved site is covered as well', () async {
    final repo = WebClearanceRepo(null);
    await repo.save(
      host: 'donmai.us',
      userAgent: 'browser',
      cookies: 'cf_clearance=abc',
    );

    final options = await _send(
      HeadersInterceptor(const FallbackEnvRepo(), repo),
      'https://cdn.donmai.us/original/aa/bb/cc.jpg',
    );

    expect(options.headers['User-Agent'], 'browser');
    expect(options.headers['Cookie'], 'cf_clearance=abc');
  });

  test('an unsolved host keeps the app agent', () async {
    final options = await _send(
      HeadersInterceptor(const FallbackEnvRepo(), WebClearanceRepo(null)),
      'https://example.com/posts.json',
    );

    expect(options.headers['User-Agent'], 'Boorusphere/0.0.0');
    expect(options.headers.containsKey('Cookie'), isFalse);
  });

  test('a cookie from the jar survives next to the clearance', () async {
    final repo = WebClearanceRepo(null);
    await repo.save(
      host: 'danbooru.donmai.us',
      userAgent: 'browser',
      cookies: 'cf_clearance=abc',
    );

    final options = await _send(
      HeadersInterceptor(const FallbackEnvRepo(), repo),
      'https://danbooru.donmai.us/posts.json',
      headers: {'Cookie': 'login=me'},
    );

    expect(options.headers['Cookie'], 'login=me; cf_clearance=abc');
  });

  test(
    'the referer default carries only the origin, never query secrets',
    () async {
      final options = await _send(
        HeadersInterceptor(const FallbackEnvRepo(), WebClearanceRepo(null)),
        'https://example.com/index.php?page=dapi&user_id=alice&api_key=s3cr3t',
      );

      expect(options.headers['Referer'], 'https://example.com/');
    },
  );

  test('an explicit referer set by the caller is preserved', () async {
    final options = await _send(
      HeadersInterceptor(const FallbackEnvRepo(), WebClearanceRepo(null)),
      'https://cdn.example.com/images/1.jpg',
      headers: {HttpHeaders.refererHeader: 'https://example.com/posts/1'},
    );

    expect(
      options.headers[HttpHeaders.refererHeader],
      'https://example.com/posts/1',
    );
  });

  group('AppDio retry and cookie safety', () {
    test(
      'retries on 502 and 429 keep browser clearance cookies with JSON quotes without CookieManagerLoadException',
      () async {
        final jar = CookieJar();
        await jar.saveFromResponse(Uri.parse('https://booru.test/'), [
          Cookie('session_id', 'init'),
        ]);
        final clearance = WebClearanceRepo(null);
        await clearance.save(
          host: 'booru.test',
          userAgent: 'Mozilla/5.0 (Linux; Android 14)',
          cookies: 'cf_clearance=abc; g_state={"i_l":0,"i_p":1}',
        );

        final client = AppDio(
          cookieJar: jar,
          envRepo: const FallbackEnvRepo(),
          clearance: clearance,
          retryDelays: const [Duration.zero, Duration.zero],
        );
        final seenCookies = <String?>[];
        var call = 0;
        client.httpClientAdapter = _ScriptedAdapter((options) {
          seenCookies.add(
            options.headers[HttpHeaders.cookieHeader]?.toString(),
          );
          call++;
          if (call == 1) {
            return ResponseBody.fromString(
              'bad gateway',
              502,
              headers: {
                HttpHeaders.setCookieHeader: ['edge=2; Path=/'],
              },
            );
          }
          if (call == 2) {
            return ResponseBody.fromString(
              'slow down',
              429,
              headers: {
                'retry-after': ['0'],
              },
            );
          }
          return ResponseBody.fromString('["ok"]', 200);
        });

        final res = await client.get<String>('https://booru.test/posts.json');
        expect(res.statusCode, 200);
        expect(call, 3);
        expect(
          seenCookies[0],
          'session_id=init; cf_clearance=abc; g_state={"i_l":0,"i_p":1}',
        );
        expect(
          seenCookies[1],
          'session_id=init; edge=2; cf_clearance=abc; g_state={"i_l":0,"i_p":1}',
        );
        expect(
          seenCookies[2],
          'session_id=init; edge=2; cf_clearance=abc; g_state={"i_l":0,"i_p":1}',
        );
      },
    );

    test('does not retry a 503 Cloudflare challenge', () async {
      final client = AppDio(
        cookieJar: CookieJar(),
        envRepo: const FallbackEnvRepo(),
        clearance: WebClearanceRepo(null),
        retryDelays: const [Duration.zero, Duration.zero],
      );
      var calls = 0;
      client.httpClientAdapter = _ScriptedAdapter((_) {
        calls++;
        return ResponseBody.fromString(
          '<html><title>Just a moment...</title></html>',
          503,
          headers: {
            'cf-mitigated': ['challenge'],
          },
        );
      });

      await expectLater(
        client.get<String>('https://booru.test/posts.json'),
        throwsA(isA<DioException>()),
      );
      expect(calls, 1);
    });

    test('still retries a plain 503 upstream error', () async {
      final client = AppDio(
        cookieJar: CookieJar(),
        envRepo: const FallbackEnvRepo(),
        clearance: WebClearanceRepo(null),
        retryDelays: const [Duration.zero, Duration.zero],
      );
      var calls = 0;
      client.httpClientAdapter = _ScriptedAdapter((_) {
        calls++;
        if (calls == 1) {
          return ResponseBody.fromString('upstream unavailable', 503);
        }
        return ResponseBody.fromString('ok', 200);
      });

      final res = await client.get<String>('https://booru.test/posts.json');
      expect(res.statusCode, 200);
      expect(calls, 2);
    });
  });
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
