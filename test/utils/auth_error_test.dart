import 'dart:convert';
import 'dart:typed_data';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/utils/http/auth_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _error({required int status, Object? data}) {
  final options = RequestOptions(
    path: 'https://api.rule34.xxx/index.php?page=dapi&s=post&q=index',
  );
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: data,
    ),
  );
}

/// The line Rule34's API host answers an anonymous `dapi` request with.
const _notice =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<error>Missing authentication. Go to api.rule34.xxx for more '
    'information</error>';

void main() {
  group('isAuthRequired', () {
    test('recognises the mapped error the repository throws', () {
      expect(isAuthRequired(BooruError.authRequired), isTrue);
    });

    test('reads the status a server that wants a login answers with', () {
      expect(isAuthRequired(_error(status: 401)), isTrue);
      expect(isAuthRequired(_error(status: 401, data: 'Unauthorized')), isTrue);
    });

    test('leaves a rejection that is not about the account alone', () {
      // 403 is the hotlink and Cloudflare family, 429 the rate limit; both say
      // "try differently", not "add a key".
      expect(isAuthRequired(_error(status: 403)), isFalse);
      expect(isAuthRequired(_error(status: 429)), isFalse);
      expect(isAuthRequired(_error(status: 500)), isFalse);
    });

    test('leaves another failure alone', () {
      expect(isAuthRequired(StateError('offline')), isFalse);
      expect(isAuthRequired(BooruError.unparsable), isFalse);
      expect(isAuthRequired(null), isFalse);
    });
  });

  group('isAuthFailureBody', () {
    test('reads the XML error element served under a success status', () {
      expect(isAuthFailureBody(_notice), isTrue);
    });

    test('reads the same line as a bare string', () {
      expect(
        isAuthFailureBody(
          'Missing authentication. '
          'Go to api.rule34.xxx for more information',
        ),
        isTrue,
      );
    });

    test('reads it whatever case the engine put it in', () {
      expect(isAuthFailureBody('MISSING AUTHENTICATION'), isTrue);
      expect(isAuthFailureBody('  missing authentication  '), isTrue);
    });

    test('ignores a page that merely mentions authentication', () {
      // A real result set, an interstitial or an error template is far larger
      // than the one-line notice. Matching inside it would blame the account
      // for a payload the reader can see with their own browser.
      final page = '<html><body>${'<p>missing authentication</p>' * 80}</body>';
      expect(page.length, greaterThan(512));
      expect(isAuthFailureBody(page), isFalse);
    });

    test('ignores a result and an empty body', () {
      expect(isAuthFailureBody('{"@attributes":{"count":0}}'), isFalse);
      expect(isAuthFailureBody('[]'), isFalse);
      expect(isAuthFailureBody(''), isFalse);
    });
  });

  group('isAuthFailurePayload', () {
    test('accepts the notice as bytes, which is how it is fetched', () {
      expect(
        isAuthFailurePayload(Uint8List.fromList(utf8.encode(_notice))),
        isTrue,
      );
    });

    test('accepts it as the text the decoder hands over', () {
      expect(isAuthFailurePayload(_notice), isTrue);
    });

    test('leaves an already-decoded result alone', () {
      expect(isAuthFailurePayload(const <Object>[]), isFalse);
      expect(isAuthFailurePayload(const {'results': []}), isFalse);
      expect(isAuthFailurePayload(null), isFalse);
    });

    test('does not decode a payload larger than the notice can be', () {
      final bytes = Uint8List.fromList(
        utf8.encode('${'x' * 4096}missing authentication'),
      );
      expect(isAuthFailurePayload(bytes), isFalse);
    });
  });
}
