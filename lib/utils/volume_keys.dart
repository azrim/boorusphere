import 'package:boorusphere/utils/logger.dart';
import 'package:flutter/services.dart';

enum VolumeKeyDirection { up, down }

/// Android volume keys, forwarded to Dart while a post viewer asks for them.
///
/// The platform side consumes the key only while at least one viewer holds a
/// token, so everywhere else the buttons keep their normal volume behaviour.
/// Viewers stack (a related post opens another timeline), and only the one
/// actually on screen may answer. [acquire] makes the newest token the
/// dispatcher; [release] hands dispatch back to the viewer underneath, without
/// waiting for the two to run in any particular order.
class VolumeKeys {
  const VolumeKeys._();

  static const MethodChannel _channel = MethodChannel(
    'io.chaldeaprjkt.boorusphere/volume_keys',
  );

  /// Insertion ordered: the last entry is the viewer acquired most recently.
  static final Map<Object, void Function(VolumeKeyDirection direction)>
  _handlers = <Object, void Function(VolumeKeyDirection)>{};
  static Object? _activeToken;
  static bool _installed = false;

  /// Registers [handler] as the viewer to forward keys to, and starts native
  /// capture if this is the first viewer.
  static Future<void> acquire(
    Object token,
    void Function(VolumeKeyDirection direction) handler,
  ) async {
    _install();
    final wasIdle = _handlers.isEmpty;
    _handlers
      ..remove(token)
      ..[token] = handler;
    _activeToken = token;
    if (wasIdle) await _setEnabled(true);
  }

  /// Withdraws [token]. Capture stops with the last viewer; otherwise the
  /// viewer below takes over if this one was answering.
  static Future<void> release(Object token) async {
    if (_handlers.remove(token) == null) return;

    if (_handlers.isNotEmpty) {
      if (_activeToken == token) {
        _activeToken = _handlers.keys.last;
      }
      return;
    }

    _activeToken = null;
    await _setEnabled(false);
  }

  static void _install() {
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onVolumeKey') return null;
      final handler = _handlers[_activeToken];
      if (handler == null) return null;
      switch (call.arguments) {
        case 'up':
          handler(VolumeKeyDirection.up);
        case 'down':
          handler(VolumeKeyDirection.down);
      }
      return null;
    });
  }

  static Future<void> _setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // Not Android, or a test harness without the host: the preference is
      // simply a no-op there.
    } on PlatformException catch (e, stack) {
      mainLog.w('Volume keys: failed to change capture state', e, stack);
    }
  }
}
