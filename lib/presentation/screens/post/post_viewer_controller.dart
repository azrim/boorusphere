import 'dart:async';

import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ViewMode { horizontal, vertical }

@immutable
class PostViewerState {
  const PostViewerState({
    required this.page,
    this.swipeEnabled = true,
    this.animating = false,
    this.overlayVisible = true,
    this.forceHideOverlay = false,
  });

  final int page;
  final bool swipeEnabled;
  final bool animating;
  final bool overlayVisible;
  final bool forceHideOverlay;

  bool get canSwipe => swipeEnabled && !animating;
  bool get isOverlayShown => overlayVisible && !forceHideOverlay;

  PostViewerState copyWith({
    int? page,
    bool? swipeEnabled,
    bool? animating,
    bool? overlayVisible,
    bool? forceHideOverlay,
  }) {
    return PostViewerState(
      page: page ?? this.page,
      swipeEnabled: swipeEnabled ?? this.swipeEnabled,
      animating: animating ?? this.animating,
      overlayVisible: overlayVisible ?? this.overlayVisible,
      forceHideOverlay: forceHideOverlay ?? this.forceHideOverlay,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PostViewerState &&
          runtimeType == other.runtimeType &&
          page == other.page &&
          swipeEnabled == other.swipeEnabled &&
          animating == other.animating &&
          overlayVisible == other.overlayVisible &&
          forceHideOverlay == other.forceHideOverlay;

  @override
  int get hashCode => Object.hash(
    page,
    swipeEnabled,
    animating,
    overlayVisible,
    forceHideOverlay,
  );
}

class PostViewerController extends ValueNotifier<PostViewerState> {
  PostViewerController({
    required this.initialPage,
    required this.totalPages,
    this.viewMode = ViewMode.horizontal,
    this.swipeMode = SwipeMode.horizontal,
  }) : _pageController = PageController(initialPage: initialPage),
       super(PostViewerState(page: initialPage));

  final int initialPage;
  final int totalPages;
  final ViewMode viewMode;
  final SwipeMode swipeMode;

  final PageController _pageController;
  PageController get pageController => _pageController;

  late final ValueListenable<int> pageListenable = _Selected<int>(
    this,
    (s) => s.page,
  );
  late final ValueListenable<bool> canSwipeListenable = _Selected<bool>(
    this,
    (s) => s.canSwipe,
  );
  late final ValueListenable<bool> overlayShownListenable = _Selected<bool>(
    this,
    (s) => s.isOverlayShown,
  );

  int get page => value.page;
  bool get isFirstPage => page <= 0;
  bool get isLastPage => page >= totalPages - 1;

  void updateCurrentPage(int page) {
    value = value.copyWith(page: page);
  }

  void enableSwipe() {
    value = value.copyWith(swipeEnabled: true);
  }

  void disableSwipe() {
    value = value.copyWith(swipeEnabled: false);
  }

  void showOverlay() {
    value = value.copyWith(overlayVisible: true);
  }

  void hideOverlay() {
    value = value.copyWith(overlayVisible: false);
  }

  void toggleOverlay() {
    value = value.copyWith(overlayVisible: !value.overlayVisible);
  }

  void forceHideUI() {
    value = value.copyWith(forceHideOverlay: true);
  }

  void restoreUI() {
    value = value.copyWith(forceHideOverlay: false);
  }

  Future<void> nextPage({Duration? duration}) async {
    if (isLastPage) return;
    value = value.copyWith(animating: true);
    try {
      await _pageController.nextPage(
        duration: duration ?? const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } finally {
      value = value.copyWith(animating: false);
    }
  }

  Future<void> previousPage({Duration? duration}) async {
    if (isFirstPage) return;
    value = value.copyWith(animating: true);
    try {
      await _pageController.previousPage(
        duration: duration ?? const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } finally {
      value = value.copyWith(animating: false);
    }
  }

  Future<void> animateToPage(int page, {Duration? duration}) async {
    if (page < 0 || page >= totalPages) return;
    value = value.copyWith(animating: true);
    try {
      await _pageController.animateToPage(
        page,
        duration: duration ?? const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } finally {
      value = value.copyWith(animating: false);
    }
  }

  void jumpToPage(int page) {
    if (page < 0 || page >= totalPages) return;
    _pageController.jumpToPage(page);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

class _Selected<R> extends ChangeNotifier implements ValueListenable<R> {
  _Selected(this._source, this._selector) : _value = _selector(_source.value) {
    _source.addListener(_update);
  }

  final ValueListenable<PostViewerState> _source;
  final R Function(PostViewerState) _selector;
  R _value;

  @override
  R get value => _value;

  void _update() {
    final next = _selector(_source.value);
    if (next != _value) {
      _value = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _source.removeListener(_update);
    super.dispose();
  }
}
