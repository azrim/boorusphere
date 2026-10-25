import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/favorite_post/entity/favorite_post.dart';
import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/data/repository/search_history/user_search_history.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/booru_tags_blocker_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../utils/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hiveContainer = HiveTestContainer();

  tearDownAll(hiveContainer.dispose);

  group('UserFavoritePostRepo.import', () {
    late Box<FavoritePost> box;
    late UserFavoritePostRepo repo;

    setUp(() async {
      box = await Hive.openBox<FavoritePost>(UserFavoritePostRepo.key);
      await box.clear();
      repo = UserFavoritePostRepo(box);
    });

    test('a malformed entry throws and keeps the stored favorites', () async {
      await repo.save(const Post(id: 1, serverId: 'srv'));

      await expectLater(
        repo.import(
          jsonEncode([
            {'post': 'oops', 'timestamp': 1},
          ]),
        ),
        throwsA(anything),
      );

      expect(box.length, 1);
      expect(box.values.single.post.id, 1);
    });

    test('a valid import replaces the stored list', () async {
      await repo.save(const Post(id: 1, serverId: 'srv'));
      final payload = jsonEncode([
        const FavoritePost(
          post: Post(id: 2, serverId: 'srv'),
          timestamp: 1,
        ).toJson(),
      ]);

      await repo.import(payload);

      expect(box.keys, ['2@srv']);
      expect(box.values.single.post.id, 2);
    });
  });

  group('UserSearchHistoryRepo.import', () {
    late Box<SearchHistory> box;
    late UserSearchHistoryRepo repo;

    setUp(() async {
      box = await Hive.openBox<SearchHistory>(UserSearchHistoryRepo.key);
      await box.clear();
      repo = UserSearchHistoryRepo(box);
    });

    test('a malformed entry throws and keeps the stored history', () async {
      await repo.save('cat', 'srv');

      await expectLater(
        repo.import(
          jsonEncode([
            {'query': 1},
          ]),
        ),
        throwsA(anything),
      );

      expect(box.length, 1);
      expect(box.values.single.query, 'cat');
    });

    test('a valid import keeps the backup order', () async {
      await repo.save('old', 'srv');
      final payload = jsonEncode([
        const SearchHistory(query: 'a', server: 'srv').toJson(),
        const SearchHistory(query: 'b', server: 'srv').toJson(),
      ]);

      await repo.import(payload);

      expect(box.keys, [0, 1]);
      expect(box.values.map((it) => it.query), ['a', 'b']);
    });
  });

  group('BooruTagsBlockerRepo.import', () {
    late Box<BooruTag> box;
    late BooruTagsBlockerRepo repo;

    setUp(() async {
      box = await Hive.openBox<BooruTag>(BooruTagsBlockerRepo.boxKey);
      await box.clear();
      repo = BooruTagsBlockerRepo(box);
    });

    test('a malformed entry throws and keeps the stored blocklist', () async {
      await repo.push(const BooruTag(name: 'cat'));

      await expectLater(
        repo.import(
          jsonEncode([
            {'name': 1},
          ]),
        ),
        throwsA(anything),
      );

      expect(box.length, 1);
      expect(box.values.single.name, 'cat');
    });

    test('a valid import trims and deduplicates the entries', () async {
      await repo.push(const BooruTag(name: 'old'));
      final payload = jsonEncode([
        {'name': ' cat ', 'serverId': ''},
        {'name': 'cat'},
        'dog',
      ]);

      await repo.import(payload);

      expect(box.values.map((it) => it.name), ['cat', 'dog']);
    });
  });

  group('UserServerRepo.import', () {
    late Box<Server> box;
    late UserServerRepo repo;

    setUp(() async {
      box = await Hive.openBox<Server>(UserServerRepo.key);
      await box.clear();
      repo = UserServerRepo(defaultServers: const {}, box: box);
    });

    test('a malformed entry keeps the stored servers', () async {
      await box.put('@keep', const Server(id: 'keep'));

      await repo.import(
        jsonEncode([
          {'id': 5},
        ]),
      );

      expect(box.keys, ['@keep']);
    });

    test('a valid import replaces the stored list', () async {
      await box.put('@drop', const Server(id: 'drop'));
      await box.put('@keep', const Server(id: 'keep'));

      await repo.import(jsonEncode([const Server(id: 'keep').toJson()]));

      expect(box.keys, ['@keep']);
      expect(box.values.single.id, 'keep');
    });

    test(
      'an outside payload restores both servers with their credentials',
      () async {
        await repo.import(
          jsonEncode([
            {
              'id': 'signed',
              'homepage': 'https://signed.example',
              'apiAddr': 'https://signed.example/api',
              'login': 'user',
              'apiKey': 'secret',
            },
            {'id': 'anon', 'homepage': 'https://anon.example'},
          ]),
        );

        expect(box.keys, unorderedEquals(['@signed', '@anon']));
        final signed = box.get('@signed');
        expect(signed?.login, 'user');
        expect(signed?.apiKey, 'secret');
        expect(box.get('@anon')?.login, '');
        expect(box.get('@anon')?.apiKey, '');
      },
    );
  });

  group('UserServerRepo.export', () {
    late Box<Server> box;
    late UserServerRepo repo;

    setUp(() async {
      box = await Hive.openBox<Server>(UserServerRepo.key);
      await box.clear();
      repo = UserServerRepo(defaultServers: const {}, box: box);
    });

    test('the export carries the stored credentials', () async {
      await box.put(
        '@srv',
        const Server(id: 'srv', login: 'user', apiKey: 'secret'),
      );

      final exported = (await repo.export()).value as List;

      expect(exported.single['login'], 'user');
      expect(exported.single['apiKey'], 'secret');
    });

    test('a round-trip import keeps the credentials', () async {
      await box.put(
        '@srv',
        const Server(id: 'srv', login: 'user', apiKey: 'secret'),
      );
      final payload = jsonEncode((await repo.export()).value);

      await box.clear();
      await repo.import(payload);

      expect(box.values.single.login, 'user');
      expect(box.values.single.apiKey, 'secret');
    });
  });
}
