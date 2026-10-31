import 'package:boorusphere/utils/logger.dart';
import 'package:flutter/services.dart';

/// Android's FLAG_SECURE, controlled from Dart.
///
/// The flag keeps the window out of the recents preview and refuses
/// screenshots; it is a window property, so the platform side owns it and this
/// class only sends the wanted state.
class SecureScreen {
  const SecureScreen._();

  static const MethodChannel _channel = MethodChannel(
    'io.chaldeaprjkt.boorusphere/secure',
  );

  static Future<void> setFlagSecure(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setFlagSecure', {'enabled': enabled});
    } on MissingPluginException {
      // A test harness or a platform without the channel has no window to
      // protect; the preference is still stored and reported by the app.
    } on PlatformException catch (e, stack) {
      mainLog.w('Secure screen: failed to set FLAG_SECURE', e, stack);
    }
  }
}
