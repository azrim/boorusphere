import 'package:flutter/gestures.dart';

/// Vertical drag recognizer that rejects itself the moment a 2nd pointer
/// arrives. This prevents pinch-to-zoom from racing with vertical drag
/// recognition — [InteractiveViewer]'s [ScaleGestureRecognizer] wins
/// uncontested when two fingers are down.
///
/// The default [VerticalDragGestureRecognizer] tracks all incoming
/// pointers and decides whether to claim based on dominant motion —
/// which can race with scale recognition during a pinch that includes
/// any vertical component, leaving the user unable to zoom.
class SinglePointerVerticalDragRecognizer
    extends VerticalDragGestureRecognizer {
  SinglePointerVerticalDragRecognizer({super.debugOwner});

  final Set<int> _activePointers = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      // Multi-touch — yield to [InteractiveViewer]'s scale recognizer.
      //
      // We deliberately do NOT call `super.addAllowedPointer(event)`
      // for this 2nd+ pointer — we don't want to track its drag. But
      // because we never tracked it, Flutter never routes its
      // up/cancel events to us, and `rejectGesture(pointer)` /
      // `didStopTrackingLastPointer(pointer)` are NEVER fired for this
      // pointer either. If we leave [event.pointer] in [_activePointers]
      // it leaks: the next pointer-down event we see will count it
      // toward the multi-touch threshold even though the finger is
      // long gone, and the recognizer will silently self-reject every
      // subsequent single-finger gesture.
      //
      // Fix: explicitly remove the new pointer from our local set
      // before resolving. Pointer 1 (the one in arena) gets cleaned up
      // via `rejectGesture` / `didStopTrackingLastPointer` as usual.
      _activePointers.remove(event.pointer);
      resolve(GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
  }

  @override
  void rejectGesture(int pointer) {
    _activePointers.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _activePointers.remove(pointer);
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  String get debugDescription => 'single_pointer_vertical_drag';
}
