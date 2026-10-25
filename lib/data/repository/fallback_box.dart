import 'package:boorusphere/utils/logger.dart';
import 'package:hive_ce/hive.dart';

/// Stand-in boxes, keyed by the name the app asked for at boot.
final Map<String, Box> _fallbacks = {};

/// Prefix that keeps a stand-in from ever colliding with a real box name.
const _fallbackPrefix = '__unavailable_';

/// Opens an empty box under a spare name and registers it as the stand-in for
/// [name].
///
/// The real box keeps its file on disk untouched, so a later launch that can
/// open it still finds every entry: only the reads and writes made while it is
/// unavailable go to the stand-in. The stand-in is emptied on open so entries
/// left by an earlier failed run are not shown as current.
Future<void> openFallbackBox<T>(String name) async {
  if (_fallbacks.containsKey(name)) return;
  final box = await Hive.openBox<T>('$_fallbackPrefix$name');
  await box.clear();
  _fallbacks[name] = box;
  mainLog.w('FallbackBox: "$name" is unavailable, using an empty stand-in');
}

/// The empty stand-in registered for [name], or null when its box was opened
/// normally.
Box<T>? fallbackFor<T>(String name) {
  final box = _fallbacks[name];
  return box is Box<T> ? box : null;
}
