import 'dart:async';

import 'package:boorusphere/utils/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen awake while at least one post viewer is visible.
///
/// `wakelock_plus` is a single process-wide switch with no reference counting
/// of its own. A viewer covered by another route still holds its request, and
/// two stacked viewers each turn the switch off on their way out, leaving the
/// one still on screen without it. The manager counts only the viewers that
/// are actually on top.
class WakelockManager {
  WakelockManager({Future<void> Function(bool enabled)? setEnabled})
    : _setEnabled = setEnabled ?? _platformSetEnabled;

  /// Test seam; the default talks to the plugin.
  final Future<void> Function(bool enabled) _setEnabled;

  final Set<Object> _holders = <Object>{};
  bool _enabled = false;

  /// Adds [holder]; the first one turns the switch on.
  void acquire(Object holder) {
    if (!_holders.add(holder)) return;
    if (_holders.length > 1) return;

    _enabled = true;
    unawaited(_setEnabled(true));
  }

  /// Removes [holder]; the switch goes off with the last one.
  void release(Object holder) {
    if (!_holders.remove(holder)) return;
    if (_holders.isNotEmpty || !_enabled) return;

    _enabled = false;
    unawaited(_setEnabled(false));
  }

  static Future<void> _platformSetEnabled(bool enabled) async {
    try {
      await (enabled ? WakelockPlus.enable() : WakelockPlus.disable());
    } catch (e, stack) {
      mainLog.w('Wakelock: failed to change the screen-on request', e, stack);
    }
  }
}

/// The app has one viewer stack, so it has one manager.
final WakelockManager wakelockManager = WakelockManager();
