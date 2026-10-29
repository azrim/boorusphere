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

  group('UserServerRepo.populate suggestion URLs', () {
    const safebooruHome = 'https://safebooru.org';
    const autocompleteUrl = 'autocomplete.php?q={tag-part}';
    const gelbooruAutocompleteUrl =
        'index.php?page=autocomplete2&term={tag-part}&type=tag_query&limit={post-limit}';

    late Box<Server> box;
    late UserServerRepo repo;

    setUp(() async {
      box = await Hive.openBox<Server>('server_url_test');
      await box.clear();
      repo = UserServerRepo(
        defaultServers: const {'@seed': Server(id: 'seed')},
        box: box,
      );
    });

    tearDown(() => box.close());

    test('restores the autocomplete URL a Safebooru entry lost', () async {
      await box.put(
        '@safebooru',
        const Server(
          id: 'Safebooru',
          homepage: safebooruHome,
          tagSuggestionUrl: gelbooruAutocompleteUrl,
          suggestionParserId: 'Gelbooru.autocomplete',
        ),
      );

      await repo.populate();

      final server = box.get('@safebooru')!;
      expect(server.tagSuggestionUrl, autocompleteUrl);
      expect(server.suggestionParserId, isEmpty);
    });

    test('keeps a Safebooru entry on its own autocomplete URL', () async {
      await box.put(
        '@safebooru',
        const Server(
          id: 'Safebooru',
          homepage: safebooruHome,
          tagSuggestionUrl: autocompleteUrl,
        ),
      );

      await repo.populate();

      expect(box.get('@safebooru')!.tagSuggestionUrl, autocompleteUrl);
    });

    test('still points a Gelbooru entry at autocomplete2', () async {
      await box.put(
        '@gelbooru',
        const Server(
          id: 'Gelbooru',
          homepage: 'https://gelbooru.com',
          tagSuggestionUrl:
              'index.php?page=dapi&s=tag&q=index&name_pattern=%{tag-part}%&orderby=count&limit={post-limit}&json=1',
        ),
      );

      await repo.populate();

      expect(box.get('@gelbooru')!.tagSuggestionUrl, gelbooruAutocompleteUrl);
    });
  });
}
