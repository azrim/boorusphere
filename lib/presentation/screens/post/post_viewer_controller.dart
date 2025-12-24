import 'dart:async';

import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:flutter/material.dart';

enum ViewMode {
  horizontal,
  vertical,
}

class PostViewerController {
  PostViewerController({
    required this.initialPage,
    required this.totalPages,
    this.viewMode = ViewMode.horizontal,
    this.swipeMode = SwipeMode.horizontal,
  }) : _pageController = PageController(initialPage: initialPage);

  final int initialPage;
  final int totalPages;
  final ViewMode viewMode;
  final SwipeMode swipeMode;

  final PageController _pageController;
  PageController get pageController => _pageController;

  // Current page tracking
  final ValueNotifier<int> _currentPage = ValueNotifier(0);
  ValueNotifier<int> get currentPage => _currentPage;

  // Precise page for smooth animations
  final ValueNotifier<double?> _precisePage = ValueNotifier(null);
  ValueNotifier<double?> get precisePage => _precisePage;

  // Swipe state management
  final ValueNotifier<bool> _swipeEnabled = ValueNotifier(true);
  ValueNotifier<bool> get swipeEnabled => _swipeEnabled;

  // Gesture state
  final ValueNotifier<bool> _pulling = ValueNotifier(false);
  ValueNotifier<bool> get pulling => _pulling;

  final ValueNotifier<bool> _canPull = ValueNotifier(true);
  ValueNotifier<bool> get canPull => _canPull;

  // Freestyle movement for swipe-to-dismiss
  final ValueNotifier<Offset> _freestyleMoveOffset = ValueNotifier(Offset.zero);
  ValueNotifier<Offset> get freestyleMoveOffset => _freestyleMoveOffset;

  final ValueNotifier<bool> _freestyleMoving = ValueNotifier(false);
  ValueNotifier<bool> get freestyleMoving => _freestyleMoving;

  // Vertical position for sheet interaction
  final ValueNotifier<double> _verticalPosition = ValueNotifier(0);
  ValueNotifier<double> get verticalPosition => _verticalPosition;

  // UI visibility
  final ValueNotifier<bool> _overlayVisible = ValueNotifier(true);
  ValueNotifier<bool> get overlayVisible => _overlayVisible;

  final ValueNotifier<bool> _forceHideOverlay = ValueNotifier(false);
  ValueNotifier<bool> get forceHideOverlay => _forceHideOverlay;

  // Animation state
  final ValueNotifier<bool> _animating = ValueNotifier(false);
  ValueNotifier<bool> get animating => _animating;

  Timer? _cooldownTimer;

  int get page => _currentPage.value;
  bool get isFirstPage => page <= 0;
  bool get isLastPage => page >= totalPages - 1;

  void updateCurrentPage(int page) {
    _currentPage.value = page;
  }

  void updatePrecisePage(double? page) {
    _precisePage.value = page;
  }

  void enableSwipe() {
    _swipeEnabled.value = true;
  }

  void disableSwipe() {
    _swipeEnabled.value = false;
  }

  void showOverlay() {
    _overlayVisible.value = true;
  }

  void hideOverlay() {
    _overlayVisible.value = false;
  }

  void toggleOverlay() {
    _overlayVisible.value = !_overlayVisible.value;
  }

  void forceHideUI() {
    _forceHideOverlay.value = true;
  }

  void restoreUI() {
    _forceHideOverlay.value = false;
  }

  Future<void> nextPage({Duration? duration}) async {
    if (isLastPage) return;

    _animating.value = true;
    await _pageController.nextPage(
      duration: duration ?? const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _animating.value = false;
  }

  Future<void> previousPage({Duration? duration}) async {
    if (isFirstPage) return;

    _animating.value = true;
    await _pageController.previousPage(
      duration: duration ?? const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _animating.value = false;
  }

  Future<void> animateToPage(int page, {Duration? duration}) async {
    if (page < 0 || page >= totalPages) return;

    _animating.value = true;
    await _pageController.animateToPage(
      page,
      duration: duration ?? const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _animating.value = false;
  }

  void jumpToPage(int page) {
    if (page < 0 || page >= totalPages) return;
    _pageController.jumpToPage(page);
  }

  void startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(const Duration(milliseconds: 500), enableSwipe);
  }

  void dragUpdate(DragUpdateDetails details) {
    final dy = details.delta.dy;

    if (_canPull.value && dy > 0) {
      _freestyleMoving.value = true;
      _verticalPosition.value += dy;
    }
  }

  void dragEnd() {
    _pulling.value = false;
    _freestyleMoving.value = false;
    _verticalPosition.value = 0;
  }

  void dispose() {
    _cooldownTimer?.cancel();
    _pageController.dispose();
    _currentPage.dispose();
    _precisePage.dispose();
    _swipeEnabled.dispose();
    _pulling.dispose();
    _canPull.dispose();
    _freestyleMoveOffset.dispose();
    _freestyleMoving.dispose();
    _verticalPosition.dispose();
    _overlayVisible.dispose();
    _forceHideOverlay.dispose();
    _animating.dispose();
  }
}
