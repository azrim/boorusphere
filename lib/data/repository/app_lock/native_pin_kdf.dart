import 'dart:async';

import 'package:flutter/services.dart';

/// Used only when Android's native SHA-256 KDF is available. The iteration
/// count lives in the verifier, so a fallback still checks upgraded records.
const int nativePinIterations = 200000;

class NativePinKdf {
  const NativePinKdf._();

  static const channel = MethodChannel('io.chaldeaprjkt.boorusphere/pin_kdf');

  /// Called on the main isolate; Android runs the actual KDF on its task queue.
  /// API 24/25 and hosts without the channel return null for the Dart fallback.
  static Future<Uint8List?> derive(
    String pin,
    Uint8List salt,
    int iterations,
  ) async {
    // Older text-field gates accepted non-ASCII input. Keep its exact UTF-8
    // derivation in Dart rather than depend on a device provider's encoding.
    if (pin.codeUnits.any((unit) => unit > 0x7f)) return null;
    try {
      final bytes = await channel
          .invokeMethod<Uint8List>('derive', {
            'pin': pin,
            'salt': salt,
            'iterations': iterations,
          })
          .timeout(const Duration(seconds: 5));
      return bytes?.length == 32 ? bytes : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
