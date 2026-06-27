import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

final timelineControllerProvider =
    ChangeNotifierProvider.autoDispose<TimelineController>((ref) {
      return TimelineController(
        scrollController: AutoScrollController(),
        onLoadMore:
            null, // Default to null, will be overridden in specific contexts
      );
    });

class TimelineController extends ChangeNotifier {
  TimelineController({required this.scrollController, this.onLoadMore}) {
    scrollController.addListener(_autoLoadMore);
  }

  final AutoScrollController scrollController;
  final Future<void> Function()? onLoadMore;
  bool _isLoading = false;

  Future<void> _autoLoadMore() async {
    if (!scrollController.hasClients) return;
    if (_isLoading) return;
    if (scrollController.position.extentAfter < 200) {
      _isLoading = true;
      try {
        await onLoadMore?.call();
      } finally {
        _isLoading = false;
      }
    }
  }

  void scrollTo(int index) {
    if (!scrollController.hasClients) return;
    scrollController.scrollToIndex(index);
  }

  @override
  void dispose() {
    scrollController.removeListener(_autoLoadMore);
    super.dispose();
  }
}
