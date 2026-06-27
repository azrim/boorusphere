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
      const option =
          PageOption(query: 'test', searchRating: BooruRating.safe);
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
      const option =
          PageOption(query: 'test', searchRating: BooruRating.safe);
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
      const option =
          PageOption(query: 'test', searchRating: BooruRating.safe);
      final url = server.searchUrlOf(option, page: 1);
      expect(url, contains('user_id=testuser'));
      expect(url, contains('api_key=testkey'));
    });

    test('does not append credentials when empty', () {
      const server = Server(
        homepage: 'https://danbooru.donmai.us',
        searchUrl: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
      );
      const option =
          PageOption(query: 'test', searchRating: BooruRating.safe);
      final url = server.searchUrlOf(option, page: 1);
      expect(url, isNot(contains('user_id=')));
      expect(url, isNot(contains('api_key=')));
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
      const option =
          PageOption(query: 'test', searchRating: BooruRating.explicit);
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
