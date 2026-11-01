import 'dart:math';

import 'package:boorusphere/presentation/provider/settings/entity/content_setting.dart';
import 'package:boorusphere/presentation/utils/slideshow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextSlideshowPage', () {
    test('forward walks to the end and then stops', () {
      expect(
        nextSlideshowPage(
          current: 0,
          total: 3,
          direction: SlideshowDirection.forward,
        ),
        1,
      );
      expect(
        nextSlideshowPage(
          current: 2,
          total: 3,
          direction: SlideshowDirection.forward,
        ),
        isNull,
      );
    });

    test('backward walks to the start and then stops', () {
      expect(
        nextSlideshowPage(
          current: 2,
          total: 3,
          direction: SlideshowDirection.backward,
        ),
        1,
      );
      expect(
        nextSlideshowPage(
          current: 0,
          total: 3,
          direction: SlideshowDirection.backward,
        ),
        isNull,
      );
    });

    test('random never repeats the current page', () {
      for (var seed = 0; seed < 50; seed++) {
        for (var current = 0; current < 5; current++) {
          final next = nextSlideshowPage(
            current: current,
            total: 5,
            direction: SlideshowDirection.random,
            random: Random(seed),
          );
          expect(next, isNotNull);
          expect(next, inInclusiveRange(0, 4));
          expect(next, isNot(current));
        }
      }
    });

    test('a feed with fewer than two posts has nowhere to go', () {
      for (final total in [0, 1]) {
        for (final direction in SlideshowDirection.values) {
          expect(
            nextSlideshowPage(current: 0, total: total, direction: direction),
            isNull,
          );
        }
      }
    });

    test('an out-of-range page is clamped before stepping', () {
      expect(
        nextSlideshowPage(
          current: 99,
          total: 2,
          direction: SlideshowDirection.backward,
        ),
        0,
      );
      expect(
        nextSlideshowPage(
          current: -4,
          total: 2,
          direction: SlideshowDirection.forward,
        ),
        1,
      );
    });
  });
}
