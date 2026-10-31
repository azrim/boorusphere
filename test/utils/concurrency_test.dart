import 'dart:async';

import 'package:boorusphere/utils/concurrency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapConcurrent', () {
    test('returns an empty list for no items', () async {
      final result = await mapConcurrent<int, String>(
        const [],
        limit: 4,
        action: (item, _) async => '$item',
      );

      expect(result, isEmpty);
    });

    test('keeps the input order however the calls settle', () async {
      final result = await mapConcurrent<int, int>(
        [5, 1, 4, 2, 3],
        limit: 2,
        action: (item, _) async {
          // The later items finish first, so completion order alone would
          // reorder the results.
          await Future<void>.delayed(Duration(milliseconds: 6 - item));
          return item * 10;
        },
      );

      expect(result, [50, 10, 40, 20, 30]);
    });

    test('never runs more calls at once than the limit', () async {
      var active = 0;
      var peak = 0;

      await mapConcurrent<int, void>(
        List.generate(12, (index) => index),
        limit: 3,
        action: (item, _) async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
        },
      );

      expect(peak, 3);
    });

    test('runs calls one at a time for a non-positive limit', () async {
      var active = 0;
      var peak = 0;

      await mapConcurrent<int, void>(
        List.generate(4, (index) => index),
        limit: 0,
        action: (item, _) async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
        },
      );

      expect(peak, 1);
    });

    test('still hands every item to a worker after one call fails', () async {
      final seen = <int>[];
      Completer<void>? failure;

      final future = mapConcurrent<int, int>(
        [0, 1, 2, 3, 4, 5],
        limit: 2,
        action: (item, _) async {
          seen.add(item);
          if (item == 1) {
            failure = Completer<void>();
            await failure!.future;
            throw StateError('boom');
          }
          return item;
        },
      );

      // Let the workers reach item 1 and the calls behind it.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      failure!.complete();

      await expectLater(future, throwsStateError);
      expect(seen, containsAll([0, 1, 2, 3, 4, 5]));
    });
  });
}
