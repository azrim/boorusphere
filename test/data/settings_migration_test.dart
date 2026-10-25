import 'dart:io';

import 'package:boorusphere/data/encryption.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('boorusphere_settings_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a plain box is migrated without losing its entries', () async {
    final plain = await Hive.openBox(UserSettingsRepo.key);
    await plain.put(Setting.uiBlur.name, true);
    await plain.put(Setting.uiTimelineGrid.name, 2);
    await plain.close();

    await UserSettingsRepo.prepare();

    final cipher = await EncryptionHelper.getCipher();
    final migrated = await Hive.openBox(
      UserSettingsRepo.key,
      encryptionCipher: cipher,
    );
    expect(migrated.get(Setting.uiBlur.name), isTrue);
    expect(migrated.get(Setting.uiTimelineGrid.name), 2);
    expect(await Hive.boxExists('settings_migration_backup'), isFalse);
    await migrated.close();
  });

  test('an interrupted migration is recovered from its backup', () async {
    final cipher = await EncryptionHelper.getCipher();
    final backup = await Hive.openBox(
      'settings_migration_backup',
      encryptionCipher: cipher,
    );
    await backup.put(Setting.uiBlur.name, true);
    await backup.flush();
    await backup.close();

    await UserSettingsRepo.prepare();

    final restored = await Hive.openBox(
      UserSettingsRepo.key,
      encryptionCipher: cipher,
    );
    expect(restored.get(Setting.uiBlur.name), isTrue);
    expect(await Hive.boxExists('settings_migration_backup'), isFalse);
    await restored.close();
  });
}
