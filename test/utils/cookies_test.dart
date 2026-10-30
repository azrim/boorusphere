import 'package:boorusphere/utils/http/cookies.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeCookieHeaders', () {
    test('keeps both sides', () {
      expect(
        mergeCookieHeaders('login=me', 'cf_clearance=abc'),
        'login=me; cf_clearance=abc',
      );
    });

    test('lets the browser override a cookie of the same name', () {
      expect(
        mergeCookieHeaders(
          'cf_clearance=stale; login=me',
          'cf_clearance=fresh',
        ),
        'cf_clearance=fresh; login=me',
      );
    });

    test('handles a missing side', () {
      expect(mergeCookieHeaders(null, 'a=1'), 'a=1');
      expect(mergeCookieHeaders('a=1', null), 'a=1');
      expect(mergeCookieHeaders('', ''), isEmpty);
    });

    test('drops fragments that are not name=value', () {
      expect(mergeCookieHeaders('junk; a=1; =2', null), 'a=1');
    });
  });
}
