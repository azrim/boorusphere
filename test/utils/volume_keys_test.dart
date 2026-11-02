import 'package:boorusphere/utils/volume_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.chaldeaprjkt.boorusphere/volume_keys');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final capture = <bool>[];
  final received = <String>[];

  setUp(() {
    capture.clear();
    received.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setEnabled') {
        capture.add(call.arguments['enabled'] as bool);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> press(String direction) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall('onVolumeKey', direction)),
      (_) {},
    );
  }

  test(
    'the newest viewer answers and hands the keys back when it leaves',
    () async {
      final below = Object();
      final above = Object();

      await VolumeKeys.acquire(
        below,
        (direction) => received.add('below:${direction.name}'),
      );
      await VolumeKeys.acquire(
        above,
        (direction) => received.add('above:${direction.name}'),
      );
      expect(capture, [true]);

      await press('up');
      expect(received, ['above:up']);

      await VolumeKeys.release(above);
      await press('down');
      expect(received, ['above:up', 'below:down']);
      expect(capture, [true]);

      await VolumeKeys.release(below);
      expect(capture, [true, false]);

      await press('up');
      expect(received, ['above:up', 'below:down']);
    },
  );

  test(
    'releasing a covered viewer leaves capture with the visible one',
    () async {
      final below = Object();
      final above = Object();

      await VolumeKeys.acquire(below, (_) => received.add('below'));
      await VolumeKeys.acquire(above, (_) => received.add('above'));

      // A page above the viewer is pushed: the viewer below lets go first, and
      // the switch must stay on for the one that is still visible.
      await VolumeKeys.release(below);
      expect(capture, [true]);

      await press('up');
      expect(received, ['above']);

      await VolumeKeys.release(above);
      expect(capture, [true, false]);
    },
  );
}
