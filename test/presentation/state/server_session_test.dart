import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../utils/hive.dart';
import '../../utils/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hiveContainer = HiveTestContainer();

  setUpAll(() async {
    await UserServerRepo.prepare();
    await UserSettingsRepo.prepare();
  });

  tearDownAll(hiveContainer.dispose);

  /// A container whose boot found no server at all, like a start where the
  /// server box could not be opened.
  ProviderContainer emptyBoot() {
    final ref = ProviderContainer(
      overrides: [defaultServersProvider.overrideWithValue(const {})],
    );
    ref.setupTestFor(serverStateProvider);
    ref.setupTestFor(serverSettingStateProvider);
    return ref;
  }

  group('session after a boot without servers', () {
    test('the first server added becomes the active one', () async {
      final ref = emptyBoot();
      addTearDown(ref.dispose);

      await ref.read(serverStateProvider.notifier).populate();
      expect(ref.read(serverStateProvider), isEmpty);
      expect(ref.read(serverSettingStateProvider).lastActiveId, '');

      const foo = Server(id: 'FooBooru', homepage: 'https://foo.id');
      await ref.read(serverStateProvider.notifier).add(foo);

      expect(ref.read(serverSettingStateProvider).lastActiveId, 'FooBooru');
      expect(
        ref.read(serverStateProvider).map((it) => it.id),
        contains('FooBooru'),
      );
    });

    test('another add leaves the active server alone', () async {
      final ref = emptyBoot();
      addTearDown(ref.dispose);

      await ref.read(serverStateProvider.notifier).populate();
      final active = ref.read(serverSettingStateProvider).lastActiveId;
      expect(active, isNotEmpty);

      await ref
          .read(serverStateProvider.notifier)
          .add(const Server(id: 'BarBooru', homepage: 'https://bar.id'));

      expect(ref.read(serverSettingStateProvider).lastActiveId, active);
    });
  });
}
