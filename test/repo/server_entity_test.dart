import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Server.searchUrlOf', () {
    test('standard rating appends rating: tag', () {
      const server = Server(
        homepage: 'https://danbooru.donmai.us',
        searchUrl: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
      );
      const option = PageOption(query: 'test', searchRating: BooruRating.safe);
      final url = server.searchUrlOf(option, page: 1);
      expect(url, contains('rating%3Asafe'));
      expect(url, contains('test'));
      expect(url, contains('page=1'));
    });

    test('szurubooru rating uses safety: prefix', () {
      const server = Server(
        homepage: 'https://szurubooru.test',
        searchUrl:
            'api/posts?offset={post-offset}&limit={post-limit}&tags={tags}',
      );
      const option = PageOption(query: 'test', searchRating: BooruRating.safe);
      final url = server.searchUrlOf(option, page: 1);
      expect(url, contains('safety%3Asafe'));
    });

    test('booru-on-rails strips rating prefix', () {
      const server = Server(
        homepage: 'https://test.booru-on-rails.org',
        searchUrl:
            'api/v1/json/search/images?q={tags}&per_page={post-limit}&page={page-id}',
      );
      const option = PageOption(
        query: 'rating:explicit test',
        searchRating: BooruRating.explicit,
      );
      final url = server.searchUrlOf(option, page: 1);
      expect(url, isNot(contains('rating:')));
      expect(url, contains('test'));
    });

    test('empty query uses default tag', () {
      const server = Server(
        homepage: 'https://danbooru.donmai.us',
        searchUrl: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
      );
      const option = PageOption(query: '', searchRating: BooruRating.safe);
      final url = server.searchUrlOf(option, page: 1);
      expect(url, contains(Server.defaultTag));
    });

    test('appends credentials when configured', () {
      const server = Server(
        homepage: 'https://danbooru.donmai.us',
        searchUrl: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
        login: 'testuser',
        apiKey: 'testkey',
      );
      const option = PageOption(query: 'test', searchRating: BooruRating.safe);
      final url = server.searchUrlOf(option, page: 1);
      expect(url, contains('user_id=testuser'));
      expect(url, contains('api_key=testkey'));
    });

    test('does not append credentials when empty', () {
      const server = Server(
        homepage: 'https://danbooru.donmai.us',
        searchUrl: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
      );
      const option = PageOption(query: 'test', searchRating: BooruRating.safe);
      final url = server.searchUrlOf(option, page: 1);
      expect(url, isNot(contains('user_id=')));
      expect(url, isNot(contains('api_key=')));
    });

    test('requests use the api address when configured', () {
      const server = Server(
        id: 'Rule34',
        homepage: 'https://rule34.xxx',
        apiAddr: 'https://api.rule34.xxx',
        searchUrl:
            'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}',
        tagSuggestionUrl:
            'index.php?page=dapi&s=tag&q=index&name_pattern=%{tag-part}%&limit={post-limit}',
        postUrl: 'index.php?page=post&s=view&id={post-id}',
      );
      const option = PageOption(query: 'test', searchRating: BooruRating.safe);

      expect(
        server.searchUrlOf(option, page: 1),
        startsWith('https://api.rule34.xxx/index.php?'),
      );
      expect(
        server.suggestionUrlsOf('cat'),
        startsWith('https://api.rule34.xxx/index.php?'),
      );
      // Post links stay on the homepage, the API host does not serve them.
      expect(
        server.postUrlOf(1),
        'https://rule34.xxx/index.php?page=post&s=view&id=1',
      );
    });

    test('szurubooru questionable maps to sketchy', () {
      const server = Server(
        homepage: 'https://szurubooru.test',
        searchUrl:
            'api/posts?offset={post-offset}&limit={post-limit}&tags={tags}',
      );
      const option = PageOption(
        query: 'cat',
        searchRating: BooruRating.questionable,
      );
      final url = server.searchUrlOf(option, page: 2);
      expect(url, contains('safety%3Asketchy'));
      // szurubooru uses offset, not page-id; offset = page * limit = 2 * 40 = 80
      expect(url, contains('offset=80'));
    });

    test('szurubooru explicit maps to unsafe', () {
      const server = Server(
        homepage: 'https://szurubooru.test',
        searchUrl:
            'api/posts?offset={post-offset}&limit={post-limit}&tags={tags}',
      );
      const option = PageOption(
        query: 'test',
        searchRating: BooruRating.explicit,
      );
      final url = server.searchUrlOf(option, page: 1);
      expect(url, contains('safety%3Aunsafe'));
    });

    test('substitutes post-offset for szurubooru', () {
      const server = Server(
        homepage: 'https://szurubooru.test',
        searchUrl:
            'api/posts?offset={post-offset}&limit={post-limit}&tags={tags}',
      );
      const option = PageOption(
        query: 'test',
        limit: 20,
        searchRating: BooruRating.safe,
      );
      final url = server.searchUrlOf(option, page: 3);
      // offset = page * limit = 3 * 20 = 60
      expect(url, contains('offset=60'));
      expect(url, contains('limit=20'));
    });
  });
}
