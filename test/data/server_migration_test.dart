import 'package:boorusphere/data/encryption.dart';
import 'package:boorusphere/data/repository/booru/parser/autocomplete.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/e621_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/philomena_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/shimmie_xml_parser.dart';
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
      expect(server.suggestionParserId, AutocompleteJsonParser().id);
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

  group('UserServerRepo.populate completion endpoints', () {
    // The tag-table sweep both engines served suggestions from before their
    // completion endpoints were adopted: `search[order]=count` sorts the whole
    // table on every keystroke.
    const tagTableUrl =
        'tags.json?search[name_matches]=*{tag-part}*&search[order]=count'
        '&limit={post-limit}';

    late Box<Server> box;
    late UserServerRepo repo;

    setUp(() async {
      box = await Hive.openBox<Server>('server_completion_test');
      await box.clear();
      repo = UserServerRepo(
        defaultServers: const {'@seed': Server(id: 'seed')},
        box: box,
      );
    });

    tearDown(() => box.close());

    test(
      'moves a Danbooru entry to the endpoint built for a keystroke',
      () async {
        await box.put(
          '@danbooru',
          const Server(
            id: 'Danbooru',
            homepage: 'https://danbooru.donmai.us',
            tagSuggestionUrl: tagTableUrl,
          ),
        );

        await repo.populate();

        final server = box.get('@danbooru')!;
        final parser = DanbooruJsonParser();
        expect(server.tagSuggestionUrl, parser.suggestionQuery);
        expect(
          server.suggestionParserId,
          parser.id,
          reason:
              'the completion payload shares its keys with another engine\'s, '
              'so which parser reads it decides whether the count survives',
        );
      },
    );

    test('moves a manually added e621 entry the same way', () async {
      await box.put(
        '@e621',
        const Server(
          id: 'e621',
          homepage: 'https://e621.net',
          tagSuggestionUrl: tagTableUrl,
          suggestionParserId: 'E621.json',
        ),
      );

      await repo.populate();

      final server = box.get('@e621')!;
      expect(server.tagSuggestionUrl, E621JsonParser().suggestionQuery);
      expect(server.suggestionParserId, E621JsonParser().id);
    });

    test('leaves a Danbooru clone on the table it serves', () async {
      await box.put(
        '@clone',
        const Server(
          id: 'Some booru',
          homepage: 'https://some-danbooru-clone.example',
          tagSuggestionUrl: tagTableUrl,
        ),
      );

      await repo.populate();

      expect(
        box.get('@clone')!.tagSuggestionUrl,
        tagTableUrl,
        reason: 'this app has not asked that host what it answers',
      );
    });
  });

  group('UserServerRepo.populate shimmie search path', () {
    late Box<Server> box;
    late UserServerRepo repo;

    setUp(() async {
      box = await Hive.openBox<Server>('server_shimmie_test');
      await box.clear();
      repo = UserServerRepo(
        defaultServers: const {'@seed': Server(id: 'seed')},
        box: box,
      );
    });

    tearDown(() => box.close());

    test('drops the /index.xml suffix that answers an error page', () async {
      await box.put(
        '@paheal',
        const Server(
          id: 'Paheal',
          homepage: 'https://rule34.paheal.net',
          searchParserId: 'Shimmie.xml',
          searchUrl:
              'api/danbooru/find_posts/index.xml?tags={tags}'
              '&limit={post-limit}&page={page-num}',
        ),
      );

      await repo.populate();

      expect(
        box.get('@paheal')!.searchUrl,
        ShimmieXmlParser().searchQuery,
        reason: 'a saved row must heal to the path that still answers',
      );
    });

    test('heals a row that is stale in both ways at once', () async {
      await box.put(
        '@paheal',
        const Server(
          id: 'Paheal',
          homepage: 'https://rule34.paheal.net',
          searchUrl:
              'api/danbooru/find_posts/index.xml?tags={tags}'
              '&limit={post-limit}&page={page-id}',
        ),
      );

      await repo.populate();

      expect(
        box.get('@paheal')!.searchUrl,
        ShimmieXmlParser().searchQuery,
        reason: 'the page rewrite runs first, the path rewrite after it',
      );
    });

    test('leaves a row that already uses the clean path alone', () async {
      const current =
          'api/danbooru/find_posts?tags={tags}&limit={post-limit}'
          '&page={page-num}';
      await box.put('@paheal', const Server(id: 'Paheal', searchUrl: current));

      await repo.populate();

      expect(box.get('@paheal')!.searchUrl, current);
    });

    test('keeps the autocomplete path a Shimmie site serves itself', () async {
      await box.put(
        '@paheal',
        const Server(
          id: 'Paheal',
          homepage: 'https://rule34.paheal.net',
          tagSuggestionUrl: 'autocomplete.php?q={tag-part}',
        ),
      );

      await repo.populate();

      expect(
        box.get('@paheal')!.tagSuggestionUrl,
        'autocomplete.php?q={tag-part}',
        reason: 'only a Gelbooru entry is wearing a stale template here',
      );
    });
  });

  group('UserServerRepo.populate Rule34 suggestion URL', () {
    const apiHost = 'https://api.rule34.xxx';
    const autocompleteUrl = 'autocomplete.php?q={tag-part}';
    const dapiTagUrl =
        'index.php?page=dapi&s=tag&q=index&name_pattern=%{tag-part}%'
        '&orderby=count&limit={post-limit}';
    const gelbooruAutocompleteUrl =
        'index.php?page=autocomplete2&term={tag-part}&type=tag_query'
        '&limit={post-limit}';

    late Box<Server> box;
    late UserServerRepo repo;

    setUp(() async {
      box = await Hive.openBox<Server>('server_rule34_test');
      await box.clear();
      repo = UserServerRepo(
        defaultServers: const {'@seed': Server(id: 'seed')},
        box: box,
      );
    });

    tearDown(() => box.close());

    test('leaves the tag endpoint that asks for an account', () async {
      await box.put(
        '@rule34',
        const Server(
          id: 'Rule34',
          homepage: 'https://rule34.xxx',
          apiAddr: apiHost,
          tagSuggestionUrl: dapiTagUrl,
          suggestionParserId: 'Gelbooru.xml',
        ),
      );

      await repo.populate();

      final server = box.get('@rule34')!;
      expect(server.tagSuggestionUrl, autocompleteUrl);
      expect(
        server.suggestionParserId,
        AutocompleteJsonParser().id,
        reason: 'the endpoint this host answers also names the reader of it',
      );
      expect(server.apiAddr, apiHost);
    });

    test('moves back an entry the Gelbooru rewrite caught', () async {
      await box.put(
        '@rule34',
        const Server(
          id: 'Rule34',
          homepage: 'https://rule34.xxx',
          apiAddr: apiHost,
          tagSuggestionUrl: gelbooruAutocompleteUrl,
        ),
      );

      await repo.populate();

      expect(
        box.get('@rule34')!.tagSuggestionUrl,
        autocompleteUrl,
        reason: 'that host answers autocomplete2 with an empty body',
      );
    });

    test('heals the API host and the tag endpoint in one start', () async {
      await box.put(
        '@rule34',
        const Server(
          id: 'Rule34',
          homepage: 'https://rule34.xxx',
          searchUrl:
              'index.php?page=dapi&s=post&q=index&tags={tags}'
              '&pid={page-id}&limit={post-limit}',
          tagSuggestionUrl: dapiTagUrl,
        ),
      );

      await repo.populate();

      final server = box.get('@rule34')!;
      expect(server.apiAddr, apiHost);
      expect(server.tagSuggestionUrl, autocompleteUrl);
    });

    test('leaves an entry on the endpoint that answers alone', () async {
      await box.put(
        '@rule34',
        const Server(
          id: 'Rule34',
          homepage: 'https://rule34.xxx',
          apiAddr: apiHost,
          tagSuggestionUrl: autocompleteUrl,
        ),
      );

      await repo.populate();

      expect(box.get('@rule34')!.tagSuggestionUrl, autocompleteUrl);
    });
  });

  group('UserServerRepo.populate Philomena post page', () {
    const bareId = '{post-id}';

    late Box<Server> box;
    late UserServerRepo repo;

    setUp(() async {
      box = await Hive.openBox<Server>('server_post_url_test');
      await box.clear();
      repo = UserServerRepo(
        defaultServers: const {'@seed': Server(id: 'seed')},
        box: box,
      );
    });

    tearDown(() => box.close());

    test('moves a scanned entry onto the page the site links to', () async {
      await box.put(
        '@derpibooru',
        const Server(
          id: 'Derpibooru',
          homepage: 'https://derpibooru.org',
          searchParserId: 'BooruOnRails.json',
          suggestionParserId: 'BooruOnRails.json',
          searchUrl:
              'api/v1/json/search/images?q={tags}&per_page={post-limit}&page={page-num}',
          postUrl: bareId,
        ),
      );

      await repo.populate();

      final server = box.get('@derpibooru')!;
      expect(server.postUrl, PhilomenaJsonParser().postUrl);
      expect(
        server.postUrlOf(1183740),
        'https://derpibooru.org/images/1183740',
        reason:
            'the link a reader shares is what this entry exists to build, '
            'and a bare id opens whatever route that number happens to be',
      );
    });

    test('knows the board by either parser id it pins', () async {
      await box.put(
        '@derpibooru',
        const Server(
          id: 'Derpibooru',
          homepage: 'https://derpibooru.org',
          suggestionParserId: 'BooruOnRails.json',
          postUrl: bareId,
        ),
      );

      await repo.populate();

      expect(box.get('@derpibooru')!.postUrl, 'images/{post-id}');
    });

    test('leaves an entry already on the image page alone', () async {
      await box.put(
        '@derpibooru',
        const Server(
          id: 'Derpibooru',
          homepage: 'https://derpibooru.org',
          searchParserId: 'BooruOnRails.json',
          postUrl: 'images/{post-id}',
        ),
      );

      await repo.populate();

      expect(box.get('@derpibooru')!.postUrl, 'images/{post-id}');
    });

    test('leaves a board whose post page is the bare id alone', () async {
      await box.put(
        '@ponybooru',
        const Server(
          id: 'Ponybooru',
          homepage: 'https://ponybooru.org',
          searchParserId: 'BooruOnRails.json',
          suggestionParserId: 'BooruOnRails.json',
          postUrl: bareId,
        ),
      );

      await repo.populate();

      final server = box.get('@ponybooru')!;
      expect(server.postUrl, bareId);
      expect(
        server.postUrlOf(3647542),
        'https://ponybooru.org/3647542',
        reason:
            'that is the page the board serves, to a browser and to this app '
            'alike, while its /images/ path answers a 503 flood gate',
      );
    });

    test(
      'never guesses the page for a dialect that never asked for it',
      () async {
        await box.put(
          '@gelbooru',
          const Server(
            id: 'Gelbooru',
            homepage: 'https://gelbooru.com',
            searchParserId: 'Gelbooru.xml',
            postUrl: bareId,
          ),
        );

        await repo.populate();

        expect(
          box.get('@gelbooru')!.postUrl,
          bareId,
          reason: 'this release has not asked that host where its posts live',
        );
      },
    );
  });

  group('UserServerRepo.populate key page', () {
    const gelbooruPage =
        'https://gelbooru.com/index.php?page=account&s=options';
    const rule34Page = 'https://rule34.xxx/index.php?page=account&s=options';

    late Box<Server> box;
    late UserServerRepo repo;

    setUp(() async {
      box = await Hive.openBox<Server>('server_key_page_test');
      await box.clear();
      repo = UserServerRepo(
        defaultServers: const {
          '@gelbooru': Server(
            id: 'Gelbooru',
            homepage: 'https://gelbooru.com',
            apiKeyUrl: gelbooruPage,
          ),
          '@rule34': Server(
            id: 'Rule34',
            homepage: 'https://rule34.xxx',
            apiAddr: 'https://api.rule34.xxx',
            apiKeyUrl: rule34Page,
          ),
          '@safebooru': Server(
            id: 'Safebooru',
            homepage: 'https://safebooru.org',
          ),
        },
        box: box,
      );
    });

    tearDown(() => box.close());

    test('an upgraded entry learns where its key lives', () async {
      await box.put(
        '@gelbooru',
        const Server(id: 'Gelbooru', homepage: 'https://gelbooru.com'),
      );

      await repo.populate();

      expect(
        box.get('@gelbooru')!.apiKeyUrl,
        gelbooruPage,
        reason:
            'the notice asks for credentials, and the page that issues them '
            'is the one thing the reader cannot guess',
      );
    });

    test('reads the host from the API address too', () async {
      await box.put(
        '@r34',
        const Server(id: 'R34', apiAddr: 'https://api.rule34.xxx'),
      );

      await repo.populate();

      expect(box.get('@r34')!.apiKeyUrl, rule34Page);
    });

    test('keeps the address the entry already carries', () async {
      await box.put(
        '@gelbooru',
        const Server(
          id: 'Gelbooru',
          homepage: 'https://gelbooru.com',
          apiKeyUrl: 'https://gelbooru.com/help/api',
        ),
      );

      await repo.populate();

      expect(
        box.get('@gelbooru')!.apiKeyUrl,
        'https://gelbooru.com/help/api',
        reason: 'a page the reader set themselves is not this app to rewrite',
      );
    });

    test('leaves a host this release has no key page for alone', () async {
      await box.put(
        '@safebooru',
        const Server(id: 'Safebooru', homepage: 'https://safebooru.org'),
      );

      await repo.populate();

      expect(
        box.get('@safebooru')!.apiKeyUrl,
        isEmpty,
        reason:
            'that board answers anonymous requests; a sign-up page would '
            'imply a key it never asks for',
      );
    });
  });
}
