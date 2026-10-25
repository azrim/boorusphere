import 'package:boorusphere/data/encryption.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../utils/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hiveContainer = HiveTestContainer();

  tearDownAll(hiveContainer.dispose);

  // The box holding the copy written while the plain box is rewritten.
  const migrationBox = 'server_migration';

  test('a plain box is migrated without losing its entries', () async {
    final plain = await Hive.openBox<Server>(UserServerRepo.key);
    await plain.put('@a', const Server(id: 'a', apiKey: 'k'));
    await plain.close();

    await UserServerRepo.prepare();

    final cipher = await EncryptionHelper.getCipher();
    final migrated = await Hive.openBox<Server>(
      UserServerRepo.key,
      encryptionCipher: cipher,
    );
    expect(migrated.get('@a')?.apiKey, 'k');
    expect(await Hive.boxExists(migrationBox), isFalse);
  });

  test('a leftover copy is written back on the next start', () async {
    final cipher = await EncryptionHelper.getCipher();
    final leftover = await Hive.openBox<Server>(
      migrationBox,
      encryptionCipher: cipher,
    );
    await leftover.put('@b', const Server(id: 'b', apiKey: 'k2'));
    await leftover.flush();
    await leftover.close();

    await UserServerRepo.prepare();

    final restored = await Hive.openBox<Server>(
      UserServerRepo.key,
      encryptionCipher: cipher,
    );
    expect(restored.get('@b')?.apiKey, 'k2');
    expect(await Hive.boxExists(migrationBox), isFalse);
  });

  test('an empty leftover copy is dropped without touching the box', () async {
    final cipher = await EncryptionHelper.getCipher();
    final box = await Hive.openBox<Server>(
      UserServerRepo.key,
      encryptionCipher: cipher,
    );
    await box.put('@c', const Server(id: 'c'));
    await box.flush();

    final leftover = await Hive.openBox<Server>(
      migrationBox,
      encryptionCipher: cipher,
    );
    await leftover.close();

    await UserServerRepo.prepare();

    expect(box.get('@c')?.id, 'c');
    expect(await Hive.boxExists(migrationBox), isFalse);
  });
}
