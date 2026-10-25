import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/presentation/provider/settings/periodic_backup_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/hive.dart';
import '../../../utils/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PeriodicBackupSettingState', () {
    final ref = ProviderContainer();
    final hiveContainer = HiveTestContainer();

    notifier() => ref.read(periodicBackupSettingStateProvider.notifier);
    state() => ref.read(periodicBackupSettingStateProvider);

    setUpAll(() async {
      await UserSettingsRepo.prepare();
      ref.setupTestFor(periodicBackupSettingStateProvider);
    });

    tearDownAll(() async {
      await hiveContainer.dispose();
      ref.dispose();
    });

    test('starts without a passphrase', () {
      expect(state().backupPassphrase, isEmpty);
      expect(notifier().hasPassphrase, isFalse);
    });

    test('setPassphrase trims, stores and reports it as set', () async {
      await notifier().setPassphrase('  hunter22  ');

      expect(state().backupPassphrase, 'hunter22');
      expect(notifier().hasPassphrase, isTrue);
      expect(
        Hive.box(UserSettingsRepo.key).get(Setting.backupPassphrase.name),
        'hunter22',
      );
    });

    test('an empty value clears the passphrase', () async {
      await notifier().setPassphrase('hunter22');
      await notifier().setPassphrase('   ');

      expect(state().backupPassphrase, isEmpty);
      expect(notifier().hasPassphrase, isFalse);
    });

    test('backups are not encrypted until the switch is turned on', () {
      expect(state().encryptBackup, isFalse);
    });

    test('setEncryption stores the switch and reads it back', () async {
      await notifier().setEncryption(true);

      expect(state().encryptBackup, isTrue);
      expect(
        Hive.box(UserSettingsRepo.key).get(Setting.backupEncryption.name),
        isTrue,
      );

      // A fresh build of the state reads the stored value, not just the copy
      // held in memory.
      ref.invalidate(periodicBackupSettingStateProvider);
      expect(state().encryptBackup, isTrue);

      await notifier().setEncryption(false);
      expect(state().encryptBackup, isFalse);
      expect(
        Hive.box(UserSettingsRepo.key).get(Setting.backupEncryption.name),
        isFalse,
      );
    });
  });
}
