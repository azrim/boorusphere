import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/download_folder.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('downloadFolderOf', () {
    const danbooru = Server(id: 'Danbooru', alias: 'Dan favorites');
    const safebooru = Server(id: 'SafeBooru');

    test('grouping off keeps files in the shared root', () {
      expect(
        downloadFolderOf(
          const Post(serverId: 'Danbooru'),
          servers: const [danbooru],
          groupByServer: false,
        ),
        '',
      );
    });

    test('an alias names the folder', () {
      expect(
        downloadFolderOf(
          const Post(serverId: 'Danbooru'),
          servers: const [danbooru],
          groupByServer: true,
        ),
        'Dan favorites',
      );
    });

    test('a server without an alias uses its id', () {
      expect(
        downloadFolderOf(
          const Post(serverId: 'SafeBooru'),
          servers: const [safebooru],
          groupByServer: true,
        ),
        'SafeBooru',
      );
    });

    test('a deleted server still gets a folder from the post', () {
      expect(
        downloadFolderOf(
          const Post(serverId: 'Gone'),
          servers: const [danbooru],
          groupByServer: true,
        ),
        'Gone',
      );
    });

    test('a post without a server stays in the shared root', () {
      expect(
        downloadFolderOf(
          const Post(),
          servers: const [danbooru],
          groupByServer: true,
        ),
        '',
      );
    });
  });

  group('sanitizeFolderName', () {
    test('replaces characters that cannot belong to one path segment', () {
      expect(sanitizeFolderName('a/b\\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
    });

    test('collapses whitespace and trims the ends', () {
      expect(sanitizeFolderName('  My   Site  '), 'My Site');
    });

    test('drops leading dots so the name cannot address another folder', () {
      expect(sanitizeFolderName('..'), '');
      expect(sanitizeFolderName('...hidden'), 'hidden');
      expect(sanitizeFolderName('  .hidden  '), 'hidden');
    });

    test('an empty name asks for the shared root', () {
      expect(sanitizeFolderName(''), '');
      expect(sanitizeFolderName('   '), '');
    });

    test('caps a runaway alias to one path component', () {
      expect(sanitizeFolderName('x' * 150), 'x' * 100);
    });
  });
}
