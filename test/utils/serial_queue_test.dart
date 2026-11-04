import 'package:boorusphere/utils/serial_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SerialQueue', () {
    test(
      'runs in the order asked, not the order that finished first',
      () async {
        final queue = SerialQueue();
        final order = <String>[];

        final slow = queue.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          order.add('slow');
          return 1;
        });
        final fast = queue.run(() async {
          order.add('fast');
          return 2;
        });

        expect(await Future.wait([slow, fast]), [1, 2]);
        expect(order, ['slow', 'fast']);
      },
    );

    test('a rejected action does not block the ones asked after it', () async {
      final queue = SerialQueue();

      final failed = queue.run<String>(
        () async => throw StateError('rejected'),
      );
      final next = queue.run(() async => 'still runs');

      await expectLater(failed, throwsA(isA<StateError>()));
      expect(await next, 'still runs');
    });

    test('the queue drains even when nothing awaits the failure', () async {
      final queue = SerialQueue();
      final order = <String>[];

      final failed = queue.run<String>(() async {
        order.add('failed');
        throw StateError('rejected');
      });
      await queue.run(() async {
        order.add('after');
      });

      expect(order, ['failed', 'after']);
      await expectLater(failed, throwsA(isA<StateError>()));
    });
  });
}
