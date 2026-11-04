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
  /// Bounds of the sensitivity slider, and of a stored threshold: a `Slider`
  /// asserts its value is one of its steps, so a threshold that arrives from
  /// an older or hand-edited archive is pulled back to the range the screen
  /// can show instead of opening a page that throws.
  static const minSwipeDownThreshold = 50.0;
  static const maxSwipeDownThreshold = 200.0;

  static double thresholdFrom(double value) {
    return value.clamp(minSwipeDownThreshold, maxSwipeDownThreshold).toDouble();
  }

  @override
  GestureSettingState build() {
    final repo = ref.read(settingsRepoProvider);
    return GestureSettingState(
      // The stored value is read as an Object: a name is what this build
      // writes, an index is what an older build left behind, and
      // [SwipeMode.parse] accepts both.
      swipeMode: SwipeMode.parse(
        repo.get<Object>(
          Setting.gestureSwipeMode,
          or: SwipeMode.horizontal.name,
        ),
      ),
      swipeDownThreshold: thresholdFrom(
        repo.get(Setting.gestureSwipeDownThreshold, or: 100.0),
      ),
      enableSwipeToDetails: repo.get(
        Setting.gestureEnableSwipeToDetails,
        or: true,
      ),
      enableSwipeToDismiss: repo.get(
        Setting.gestureEnableSwipeToDismiss,
        or: true,
      ),
    );
  }

  Future<void> updateSwipeMode(SwipeMode mode) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(swipeMode: mode);
    await repo.put(Setting.gestureSwipeMode, mode.name);
  }

  Future<void> updateSwipeDownThreshold(double threshold) async {
    final repo = ref.read(settingsRepoProvider);
    final value = thresholdFrom(threshold);
    state = state.copyWith(swipeDownThreshold: value);
    await repo.put(Setting.gestureSwipeDownThreshold, value);
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

  /// Puts every gesture back to its default and answers whether the defaults
  /// reached storage.
  ///
  /// A run whose settings box never opened holds the choices in memory only,
  /// so a row that reported success would be promising something the next
  /// start takes back.
  Future<bool> reset() async {
    final repo = ref.read(settingsRepoProvider);
    state = const GestureSettingState();
    await repo.put(Setting.gestureSwipeMode, SwipeMode.horizontal.name);
    await repo.put(Setting.gestureSwipeDownThreshold, 100.0);
    await repo.put(Setting.gestureEnableSwipeToDetails, true);
    await repo.put(Setting.gestureEnableSwipeToDismiss, true);
    return repo.isPersistent;
  }
}
