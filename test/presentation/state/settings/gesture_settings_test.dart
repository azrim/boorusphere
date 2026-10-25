import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
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
  });
}
