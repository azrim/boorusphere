import 'dart:convert';

import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../utils/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hiveContainer = HiveTestContainer();

  tearDownAll(hiveContainer.dispose);

  test('reads defaults when the settings box never opened', () {
    final ref = ProviderContainer();
    addTearDown(ref.dispose);

    final repo = ref.read(settingsRepoProvider);

    expect(repo.isPersistent, isFalse);
    expect(repo.get(Setting.uiTimelineGrid, or: 1), 1);
    expect(repo.get(Setting.serverLastActiveId, or: ''), '');
  });

  test('a value written without a box stays readable', () async {
    final repo = UserSettingsRepo(null);
    await repo.put(Setting.uiTimelineGrid, 2);

    expect(repo.get(Setting.uiTimelineGrid, or: 1), 2);
  });

  test('a value of another type answers with the default', () async {
    final repo = UserSettingsRepo(null);
    await repo.put(Setting.uiTimelineGrid, 'two');

    expect(repo.get(Setting.uiTimelineGrid, or: 1), 1);
  });

  group('with the box open', () {
    setUpAll(UserSettingsRepo.prepare);

    test('a write that fails keeps the stored settings', () async {
      final box = await Hive.openBox('settings_write_failure');
      await box.put(Setting.uiBlur.name, true);
      await box.flush();
      await box.close();

      // Every write now fails, which used to drop the whole backup first.
      final repo = UserSettingsRepo(box);
      await repo.import(jsonEncode({Setting.uiTimelineGrid.name: 2}));

      final reopened = await Hive.openBox('settings_write_failure');
      addTearDown(reopened.close);
      expect(reopened.get(Setting.uiBlur.name), isTrue);
      expect(reopened.get(Setting.uiTimelineGrid.name), isNull);
    });

    test(
      'import stores the new values before dropping the stale ones',
      () async {
        final repo = UserSettingsRepo(Hive.box(UserSettingsRepo.key));
        await repo.put(Setting.uiBlur, false);

        await repo.import(jsonEncode({Setting.uiTimelineGrid.name: 2}));

        expect(repo.get(Setting.uiTimelineGrid, or: 1), 2);
        expect(
          Hive.box(UserSettingsRepo.key).containsKey(Setting.uiBlur.name),
          isFalse,
        );
      },
    );

    test('export carries the Telegram credentials in the backup', () async {
      final repo = UserSettingsRepo(Hive.box(UserSettingsRepo.key));
      await repo.put(Setting.telegramBotToken, '123:abc');
      await repo.put(Setting.telegramChatId, '-100');
      await repo.put(Setting.uiBlur, true);

      final exported = (await repo.export()).value as Map;

      expect(exported.keys, contains(Setting.uiBlur.name));
      expect(exported[Setting.telegramBotToken.name], '123:abc');
      expect(exported[Setting.telegramChatId.name], '-100');
    });

    test('export leaves the archive passphrase out', () async {
      final repo = UserSettingsRepo(Hive.box(UserSettingsRepo.key));
      await repo.put(Setting.backupPassphrase, 'local-secret');
      await repo.put(Setting.uiBlur, true);

      final exported = (await repo.export()).value as Map;

      expect(exported.keys, contains(Setting.uiBlur.name));
      expect(exported.keys, isNot(contains(Setting.backupPassphrase.name)));
    });

    test(
      'import does not write the passphrase carried by an archive',
      () async {
        final repo = UserSettingsRepo(Hive.box(UserSettingsRepo.key));
        await repo.put(Setting.backupPassphrase, 'local-secret');

        await repo.import(
          jsonEncode({
            Setting.uiBlur.name: true,
            Setting.backupPassphrase.name: 'foreign-secret',
          }),
        );

        expect(repo.get(Setting.backupPassphrase, or: ''), 'local-secret');
      },
    );

    test('import does not drop the local passphrase', () async {
      final repo = UserSettingsRepo(Hive.box(UserSettingsRepo.key));
      await repo.put(Setting.backupPassphrase, 'local-secret');

      // The backup names none of the local keys, so every other stale entry
      // is dropped; the passphrase has to survive that sweep.
      await repo.import(jsonEncode({Setting.uiTimelineGrid.name: 3}));

      expect(repo.get(Setting.backupPassphrase, or: ''), 'local-secret');
    });

    test('import restores the Telegram credentials from the backup', () async {
      final repo = UserSettingsRepo(Hive.box(UserSettingsRepo.key));
      await repo.put(Setting.telegramBotToken, '123:abc');
      await repo.put(Setting.telegramChatId, '-100');

      await repo.import(
        jsonEncode({
          Setting.uiBlur.name: true,
          Setting.telegramBotToken.name: '456:foreign',
          Setting.telegramChatId.name: '-200',
        }),
      );

      expect(repo.get(Setting.telegramBotToken, or: ''), '456:foreign');
      expect(repo.get(Setting.telegramChatId, or: ''), '-200');
    });
  });
}
