import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final homeDrawerControllerProvider =
    ChangeNotifierProvider.autoDispose<HomeDrawerController>(
  (ref) => HomeDrawerController(),
);

/// Controller for the home shell drawer.
///
/// Open/closed state is exposed via [isOpenListenable] (a [ValueListenable]
/// scoped to the drawer's status, not its per-frame animation tick). The
/// underlying [AnimationController] is no longer subscribed via
/// [Listenable.addListener]; that previously caused [ChangeNotifierProvider]
/// consumers to rebuild every animation frame at 60-120 FPS, dragging the
/// entire home shell with them. Consumers that only care about the
/// open/closed transition should listen to [isOpenListenable]; consumers that
/// drive the slide animation should attach to the [AnimationController]
/// directly via [AnimatedBuilder].
class HomeDrawerController extends ChangeNotifier {
  AnimationController? _animator;
  final ValueNotifier<bool> _isOpen = ValueNotifier<bool>(false);

  ValueListenable<bool> get isOpenListenable => _isOpen;
  bool get isOpen => _isOpen.value;

  void setAnimator(AnimationController controller) {
    if (_animator != null) return;
    _animator = controller;
    _animator?.addStatusListener(_onStatusChange);
  }

  void _onStatusChange(AnimationStatus status) {
    final next = status == AnimationStatus.completed;
    if (_isOpen.value != next) {
      _isOpen.value = next;
    }
  }

  void open() {
    _animator?.forward();
  }

  Future<void> close() async {
    await _animator?.reverse();
  }

  void toggle() {
    final ani = _animator;
    if (ani != null && !ani.isAnimating) {
      ani.isCompleted ? close() : open();
    }
  }

  @override
  void dispose() {
    _animator?.removeStatusListener(_onStatusChange);
    _animator = null;
    _isOpen.dispose();
    super.dispose();
  }
}
