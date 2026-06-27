import 'package:boorusphere/presentation/utils/gestures/gesture_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GestureConfig', () {
    test('fromJson roundtrip preserves values', () {
      const original = GestureConfig(
        swipeUp: 'openDetails',
        swipeDown: 'closeSearch',
        doubleTap: 'zoom',
      );
      final json = original.toJson();
      final restored = GestureConfig.fromJson(json);
      expect(restored, original);
    });

    test('toJson omits null fields', () {
      const config = GestureConfig(swipeUp: 'action');
      final json = config.toJson();
      expect(json, {'swipeUp': 'action'});
      expect(json.containsKey('swipeDown'), isFalse);
    });

    test('fromJson with empty map yields all null', () {
      final config = GestureConfig.fromJson({});
      expect(config.swipeUp, isNull);
      expect(config.swipeDown, isNull);
      expect(config.doubleTap, isNull);
    });

    test('undefined constructor yields all null', () {
      const config = GestureConfig.undefined();
      expect(config.swipeUp, isNull);
      expect(config.swipeDown, isNull);
      expect(config.swipeLeft, isNull);
      expect(config.swipeRight, isNull);
      expect(config.doubleTap, isNull);
      expect(config.longPress, isNull);
      expect(config.tap, isNull);
    });

    test('copyWith preserves unmodified fields', () {
      const original = GestureConfig(
        swipeUp: 'a',
        swipeDown: 'b',
        tap: 'c',
      );
      final copied = original.copyWith(swipeUp: () => 'x');
      expect(copied.swipeUp, 'x');
      expect(copied.swipeDown, 'b');
      expect(copied.tap, 'c');
    });

    test('copyWith with null callback sets field to null', () {
      const original = GestureConfig(swipeUp: 'a', swipeDown: 'b');
      final copied = original.copyWith(swipeUp: () => null);
      expect(copied.swipeUp, isNull);
      expect(copied.swipeDown, 'b');
    });

    test('equality', () {
      const a = GestureConfig(swipeUp: 'x', tap: 'y');
      const b = GestureConfig(swipeUp: 'x', tap: 'y');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality', () {
      const a = GestureConfig(swipeUp: 'x');
      const b = GestureConfig(swipeUp: 'y');
      expect(a, isNot(equals(b)));
    });
  });

  group('GestureConfigExtensions', () {
    test('null config cannot handle any gesture', () {
      const GestureConfig? config = null;
      expect(config.canHandleGesture(GestureType.swipeUp), isFalse);
      expect(config.canDoubleTap, isFalse);
      expect(config.canLongPress, isFalse);
      expect(config.canTap, isFalse);
    });

    test('reports true for configured gestures', () {
      const config = GestureConfig(
        swipeUp: 'openDetails',
        doubleTap: 'zoom',
        tap: 'toggleUi',
      );
      expect(config.canHandleGesture(GestureType.swipeUp), isTrue);
      expect(config.canDoubleTap, isTrue);
      expect(config.canTap, isTrue);
      expect(config.canSwipeDown, isFalse);
      expect(config.canSwipeLeft, isFalse);
    });
  });
}
