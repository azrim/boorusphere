import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'gesture_setting_state.g.dart';

class GestureSettingState {
  const GestureSettingState({
    this.swipeMode = SwipeMode.horizontal,
    this.swipeDownThreshold = 100.0,
    this.enableSwipeToDetails = true,
    this.enableSwipeToDismiss = true,
  });

  final SwipeMode swipeMode;
  final double swipeDownThreshold;
  final bool enableSwipeToDetails;
  final bool enableSwipeToDismiss;

  GestureSettingState copyWith({
    SwipeMode? swipeMode,
    double? swipeDownThreshold,
    bool? enableSwipeToDetails,
    bool? enableSwipeToDismiss,
  }) {
    return GestureSettingState(
      swipeMode: swipeMode ?? this.swipeMode,
      swipeDownThreshold: swipeDownThreshold ?? this.swipeDownThreshold,
      enableSwipeToDetails: enableSwipeToDetails ?? this.enableSwipeToDetails,
      enableSwipeToDismiss: enableSwipeToDismiss ?? this.enableSwipeToDismiss,
    );
  }
}

@riverpod
class GestureSettingStateNotifier extends _$GestureSettingStateNotifier {
  @override
  GestureSettingState build() {
    final repo = ref.read(settingsRepoProvider);
    return GestureSettingState(
      swipeMode: SwipeMode.parse(
        repo.get(Setting.gestureSwipeMode, or: SwipeMode.horizontal.index),
      ),
      swipeDownThreshold:
          repo.get(Setting.gestureSwipeDownThreshold, or: 100.0),
      enableSwipeToDetails:
          repo.get(Setting.gestureEnableSwipeToDetails, or: true),
      enableSwipeToDismiss:
          repo.get(Setting.gestureEnableSwipeToDismiss, or: true),
    );
  }

  Future<void> updateSwipeMode(SwipeMode mode) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(swipeMode: mode);
    await repo.put(Setting.gestureSwipeMode, mode.index);
  }

  Future<void> updateSwipeDownThreshold(double threshold) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(swipeDownThreshold: threshold);
    await repo.put(Setting.gestureSwipeDownThreshold, threshold);
  }

  Future<void> toggleSwipeToDetails() async {
    final repo = ref.read(settingsRepoProvider);
    final newValue = !state.enableSwipeToDetails;
    state = state.copyWith(enableSwipeToDetails: newValue);
    await repo.put(Setting.gestureEnableSwipeToDetails, newValue);
  }

  Future<void> toggleSwipeToDismiss() async {
    final repo = ref.read(settingsRepoProvider);
    final newValue = !state.enableSwipeToDismiss;
    state = state.copyWith(enableSwipeToDismiss: newValue);
    await repo.put(Setting.gestureEnableSwipeToDismiss, newValue);
  }

  Future<void> reset() async {
    final repo = ref.read(settingsRepoProvider);
    state = const GestureSettingState();
    await repo.put(Setting.gestureSwipeMode, SwipeMode.horizontal.index);
    await repo.put(Setting.gestureSwipeDownThreshold, 100.0);
    await repo.put(Setting.gestureEnableSwipeToDetails, true);
    await repo.put(Setting.gestureEnableSwipeToDismiss, true);
  }
}
