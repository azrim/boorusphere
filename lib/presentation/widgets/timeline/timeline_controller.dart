import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

final timelineControllerProvider =
    ChangeNotifierProvider.autoDispose<TimelineController>((ref) {
      return TimelineController(scrollController: AutoScrollController());
    });

class TimelineController extends ChangeNotifier {
  TimelineController({required this.scrollController});

  final AutoScrollController scrollController;

  void scrollTo(int index) {
    if (!scrollController.hasClients) return;
    scrollController.scrollToIndex(index);
  }
}
