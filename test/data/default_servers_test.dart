import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sites whose API refuses an anonymous client, and the page each of them
/// points an applicant at.
const _keyPages = {
  'Danbooru': 'https://danbooru.donmai.us/profile',
  'Gelbooru': 'https://gelbooru.com/index.php?page=account&s=options',
  'Rule34': 'https://rule34.xxx/index.php?page=account&s=options',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('default servers', () {
    late Map<String, Server> presets;

    setUpAll(() async {
      presets = await provideDefaultServers();
      expect(presets, isNotEmpty, reason: 'the asset did not load');
    });

    test('the gated ones name the page that hands the key out', () {
      _keyPages.forEach((id, page) {
        expect(
          presets.values.firstWhere((it) => it.id == id).apiKeyUrl,
          page,
          reason:
              '$id refuses an anonymous request without telling the '
              'reader where to ask, which is the one thing they cannot guess',
        );
      });
    });

    test("a preset never points at another site's credentials page", () {
      for (final server in presets.values) {
        if (server.apiKeyUrl.isEmpty) continue;
        expect(
          Uri.parse(server.apiKeyUrl).host,
          Uri.parse(server.homepage).host,
          reason:
              '${server.id} links to ${server.apiKeyUrl}, and a key from the '
              'wrong site reads as a broken server rather than a wrong account',
        );
      }
    });

    test('the engines that answer anonymously carry no key page', () {
      // Safebooru, Konachan and Yandere serve their API to anyone: linking a
      // sign-up page would imply those searches need an account.
      for (final id in ['Safebooru', 'Konachan', 'Yandere']) {
        expect(
          presets.values.firstWhere((it) => it.id == id).apiKeyUrl,
          isEmpty,
        );
      }
    });
  });

  group('Server.apiKeyUrl', () {
    test('an entry written before the field existed still decodes', () {
      final restored = Server.fromJson(const {'id': 'Rule34', 'apiKey': 'k'});
      expect(restored.apiKeyUrl, isEmpty);
      expect(restored.apiKey, 'k');
    });

    test('the address travels with the entry through a backup', () {
      const server = Server(
        id: 'Rule34',
        apiKeyUrl: 'https://rule34.xxx/index.php?page=account&s=options',
      );

      expect(
        Server.fromJson(server.toJson()).apiKeyUrl,
        server.apiKeyUrl,
        reason:
            'a restored list that lost the page would ask the reader to '
            'find it again',
      );
    });

    test('editing an entry keeps the address it shipped with', () {
      const server = Server(id: 'Rule34', apiKeyUrl: 'https://rule34.xxx/x');

      final edited = server.copyWith(login: '42');
      expect(edited.apiKeyUrl, 'https://rule34.xxx/x');
    });
  });
}
