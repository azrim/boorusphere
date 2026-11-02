import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/screens/favorites/favorites_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../utils/fake_data.dart';

void main() {
  const server = Server(id: 'Danbooru', homepage: 'https://danbooru.donmai.us');
  const removed = Server(id: 'Gelbooru', homepage: 'https://gelbooru.com');

  late final Post post;

  setUpAll(() {
    post = getSamplePosts().first;
  });

  group('favorite tabs', () {
    test('drops favorites whose server is gone', () {
      final tabs = favoriteTabsOf(
        [
          post.copyWith(serverId: removed.id),
          post.copyWith(serverId: removed.id),
        ],
        [server],
      );

      // The records are still stored, but nothing can show or open them: the
      // page has to fall back to its empty state instead of paging through
      // zero tabs.
      expect(tabs, isEmpty);
    });

    test('keeps one tab per known server', () {
      final tabs = favoriteTabsOf(
        [
          post.copyWith(serverId: server.id),
          post.copyWith(serverId: removed.id),
        ],
        [server],
      );

      expect(tabs, hasLength(1));
      expect(tabs.single.server, server);
      expect(tabs.single.posts, hasLength(1));
    });

    test('orders the tabs by server id', () {
      const other = Server(id: 'Aaa', homepage: 'https://aaa.test');
      final tabs = favoriteTabsOf(
        [post.copyWith(serverId: server.id), post.copyWith(serverId: other.id)],
        [server, other],
      );

      expect(tabs.map((it) => it.server.id), ['Aaa', 'Danbooru']);
    });
  });
}
