import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/settings/gesture_setting_state.dart';
import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/hive.dart';
import '../../../utils/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GestureSettingState', () {
    final ref = ProviderContainer();
    final hiveContainer = HiveTestContainer();

    notifier() => ref.read(gestureSettingStateProvider.notifier);
    state() => ref.read(gestureSettingStateProvider);

    setUpAll(() async {
      await UserSettingsRepo.prepare();
      ref.setupTestFor(gestureSettingStateProvider);
    });

    tearDownAll(() async {
      await hiveContainer.dispose();
      ref.dispose();
    });

    test('updateSwipeMode stores the name instead of the index', () async {
      await notifier().updateSwipeMode(SwipeMode.vertical);

      final box = Hive.box(UserSettingsRepo.key);
      expect(box.get(Setting.gestureSwipeMode.name), 'vertical');
    });

    test('a swipeMode stored as an index still reads back', () async {
      final box = Hive.box(UserSettingsRepo.key);
      await box.put(Setting.gestureSwipeMode.name, SwipeMode.vertical.index);
      await box.flush();

      ref.invalidate(gestureSettingStateProvider);
      expect(state().swipeMode, SwipeMode.vertical);
    });

    test(
      'a stored threshold the slider cannot show reads back inside it',
      () async {
        final box = Hive.box(UserSettingsRepo.key);

        await box.put(Setting.gestureSwipeDownThreshold.name, 5000.0);
        await box.flush();
        ref.invalidate(gestureSettingStateProvider);
        expect(
          state().swipeDownThreshold,
          GestureSettingStateNotifier.maxSwipeDownThreshold,
        );

        await box.put(Setting.gestureSwipeDownThreshold.name, 1.0);
        await box.flush();
        ref.invalidate(gestureSettingStateProvider);
        expect(
          state().swipeDownThreshold,
          GestureSettingStateNotifier.minSwipeDownThreshold,
        );
      },
    );

    test('updateSwipeDownThreshold stores the value it accepted', () async {
      await notifier().updateSwipeDownThreshold(1000.0);

      expect(
        state().swipeDownThreshold,
        GestureSettingStateNotifier.maxSwipeDownThreshold,
      );
      expect(
        Hive.box(
          UserSettingsRepo.key,
        ).get(Setting.gestureSwipeDownThreshold.name),
        GestureSettingStateNotifier.maxSwipeDownThreshold,
      );
    });

    test('a reset puts the defaults back and says they are kept', () async {
      await notifier().updateSwipeMode(SwipeMode.vertical);
      await notifier().updateSwipeDownThreshold(150.0);

      expect(await notifier().reset(), isTrue);

      expect(state().swipeMode, SwipeMode.horizontal);
      expect(state().swipeDownThreshold, 100.0);
      final box = Hive.box(UserSettingsRepo.key);
      expect(box.get(Setting.gestureSwipeMode.name), 'horizontal');
      expect(box.get(Setting.gestureSwipeDownThreshold.name), 100.0);
    });
  });

  group('GestureSettingState without a settings box', () {
    // Boot could not open the box, so this run holds every write in memory.
    final ref = ProviderContainer(
      overrides: [
        settingsRepoProvider.overrideWithValue(UserSettingsRepo(null)),
      ],
    );

    notifier() => ref.read(gestureSettingStateProvider.notifier);
    state() => ref.read(gestureSettingStateProvider);

    setUpAll(() => ref.setupTestFor(gestureSettingStateProvider));
    tearDownAll(ref.dispose);

    test('a reset says the defaults will not outlive the run', () async {
      await notifier().updateSwipeDownThreshold(150.0);

      expect(await notifier().reset(), isFalse);
      // The gestures do change for this run. Only the promise that they would
      // still be there on the next start was the lie.
      expect(state().swipeDownThreshold, 100.0);
    });
  });
}
