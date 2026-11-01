import 'package:boorusphere/utils/logger.dart';
import 'package:flutter/services.dart';

enum VolumeKeyDirection { up, down }

/// Android volume keys, forwarded to Dart while the viewer asks for them.
///
/// The platform side consumes the key only while [setEnabled] is true, so
/// outside the post viewer the buttons keep their normal volume behaviour.
class VolumeKeys {
  const VolumeKeys._();

  static const MethodChannel _channel = MethodChannel(
    'io.chaldeaprjkt.boorusphere/volume_keys',
  );

  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // Not Android, or a test harness without the host: the preference is
      // simply a no-op there.
    } on PlatformException catch (e, stack) {
      mainLog.w('Volume keys: failed to change capture state', e, stack);
    }
  }

  static void setHandler(void Function(VolumeKeyDirection direction)? handler) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method != 'onVolumeKey') return null;
              switch (call.arguments) {
                case 'up':
                  handler(VolumeKeyDirection.up);
                case 'down':
                  handler(VolumeKeyDirection.down);
              }
              return null;
            },
    );
  }
}
