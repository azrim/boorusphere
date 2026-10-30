import 'dart:convert';
import 'dart:typed_data';

import 'package:boorusphere/utils/http/cloudflare.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _error({
  required int status,
  Map<String, List<String>> headers = const {},
  Object? data,
}) {
  final options = RequestOptions(path: 'https://danbooru.donmai.us/posts.json');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      headers: Headers.fromMap(headers),
      data: data,
    ),
  );
}

void main() {
  group('isCloudflareChallenge', () {
    test('reads the header Cloudflare marks a challenge with', () {
      final error = _error(
        status: 403,
        headers: {
          'cf-mitigated': ['challenge'],
        },
      );
      expect(isCloudflareChallenge(error), isTrue);
    });

    test('reads the interstitial when a proxy strips the header', () {
      final error = _error(
        status: 403,
        data: '<html><script>window._cf_chl_opt = {}</script></html>',
      );
      expect(isCloudflareChallenge(error), isTrue);
    });

    test('accepts the challenge page as bytes, which is how it is fetched', () {
      final error = _error(
        status: 403,
        data: Uint8List.fromList(
          utf8.encode('<html><title>Just a moment...</title></html>'),
        ),
      );
      expect(isCloudflareChallenge(error), isTrue);
    });

    test('leaves an ordinary 403 alone', () {
      final error = _error(status: 403, data: 'Forbidden');
      expect(isCloudflareChallenge(error), isFalse);
    });

    test('leaves another failure alone', () {
      expect(isCloudflareChallenge(_error(status: 500)), isFalse);
      expect(isCloudflareChallenge(StateError('offline')), isFalse);
      expect(isCloudflareChallenge(null), isFalse);
    });
  });
}
