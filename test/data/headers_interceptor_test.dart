import 'package:boorusphere/data/dio/headers_interceptor.dart';
import 'package:boorusphere/data/repository/env/fallback_env_repo.dart';
import 'package:boorusphere/data/repository/web_clearance/web_clearance_repo.dart';
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

  test('the referer default is still applied', () async {
    final options = await _send(
      HeadersInterceptor(const FallbackEnvRepo(), WebClearanceRepo(null)),
      'https://example.com/posts.json',
    );

    expect(options.headers.containsKey('Referer'), isTrue);
  });
}
