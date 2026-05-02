import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final homeDrawerControllerProvider =
    ChangeNotifierProvider.autoDispose<HomeDrawerController>(
      (ref) => throw UnimplementedError(),
    );

class HomeDrawerController extends ChangeNotifier {
  AnimationController? _animator;

  bool get isOpen => _animator?.isCompleted ?? false;

  void setAnimator(AnimationController controller) {
    if (_animator != null) return;
    _animator = controller;
    // Listen to status transitions only (dismissed/forward/completed/reverse)
    // rather than every animation tick. The previous `addListener` variant
    // fired notifyListeners 60-120 times per second while the drawer was
    // animating, rebuilding every consumer up the tree.
    _animator?.addStatusListener(_onStatusChanged);
  }

  void _onStatusChanged(AnimationStatus _) {
    notifyListeners();
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
    _animator?.removeStatusListener(_onStatusChanged);
    _animator = null;
    super.dispose();
  }
}
