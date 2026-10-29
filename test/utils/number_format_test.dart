import 'package:boorusphere/utils/number_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compactCount', () {
    test('keeps counts below a thousand as they are', () {
      expect(compactCount(0), '0');
      expect(compactCount(42), '42');
      expect(compactCount(999), '999');
    });

    test('rounds thousands to one decimal only while it helps', () {
      expect(compactCount(1000), '1.0k');
      expect(compactCount(1420), '1.4k');
      expect(compactCount(10000), '10k');
    });

    test('crosses into millions instead of printing 1000k', () {
      expect(compactCount(999500), '1.0M');
      expect(compactCount(1000000), '1.0M');
      expect(compactCount(1250000), '1.3M');
    });
  });
}
