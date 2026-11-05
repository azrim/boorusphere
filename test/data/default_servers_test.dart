import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/provider.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/screens/server/server_add_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The sites whose API refuses an anonymous client, and the page each of them
/// points an applicant at.
const _keyPages = {
  'Danbooru': 'https://danbooru.donmai.us/profile',
  'Gelbooru': 'https://gelbooru.com/index.php?page=account&s=options',
  'Rule34': 'https://rule34.xxx/index.php?page=account&s=options',
};

/// A URL template as the server receives it: its path, plus the parameters
/// hung off it, sorted. Two copies listing the same parameters in a different
/// order ask for the same thing; a path or a parameter that differs does not.
({String path, String params}) _address(String template) {
  final split = template.split('?');
  final params = split.length < 2 ? <String>[] : split[1].split('&')
    ..sort();
  return (path: split.first, params: params.join('&'));
}

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

    test('the preset whose answers two engines share names its reader', () {
      // `autocomplete.json` reports the same keys as Gelbooru's `autocomplete2`,
      // and the generic autocomplete reader that also matches them finds the
      // count in the label instead of the field. A preset with no parser id
      // would therefore be read by the wrong dialect and lose its categories.
      final danbooru = presets.values.firstWhere((it) => it.id == 'Danbooru');
      expect(danbooru.suggestionParserId, 'Danbooru.json');
      expect(danbooru.searchParserId, 'Danbooru.json');
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

  group('the engines offered in Add Server', () {
    test('ask the template their parser serves, and name that parser', () {
      // Every entry is a copy of a parser's own URL templates. The two copies
      // drift apart silently — the list is what a manual add writes to the box,
      // the parser is what answers the same engine elsewhere — so both are
      // read from the parser registered under the id the entry names.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final parsers = container.read(booruParsersProvider);

      for (final engine in booruEngines) {
        for (final id in {engine.searchParserId, engine.suggestionParserId}) {
          final matches = parsers.where((it) => it.id == id).toList();
          expect(
            matches,
            hasLength(1),
            reason: '$id is not a registered parser',
          );
        }

        final search = parsers.firstWhere(
          (it) => it.id == engine.searchParserId,
        );
        final suggestion = parsers.firstWhere(
          (it) => it.id == engine.suggestionParserId,
        );

        expect(engine.searchQuery, isNotEmpty);
        expect(engine.suggestionQuery, isNotEmpty);
        expect(
          engine.suggestionQuery,
          contains('{tag-part}'),
          reason:
              '${engine.name} offers a suggestion URL no server will substitute',
        );
        // A parser that declares no template of its own borrows another
        // engine's URL — e621 answers posts.json exactly as Danbooru does — so
        // only the ones that do declare it can disagree with the list.
        // Compared as path plus sorted parameters: the order the two copies
        // list their parameters in is theirs, the parameters themselves are not.
        if (search.searchQuery.isNotEmpty) {
          expect(
            _address(search.searchQuery),
            _address(engine.searchQuery),
            reason: '${engine.name} writes a search template of its own',
          );
        }
        if (suggestion.suggestionQuery.isNotEmpty) {
          expect(
            _address(suggestion.suggestionQuery),
            _address(engine.suggestionQuery),
            reason: '${engine.name} writes a suggestion template of its own',
          );
        }
        // The post page is the third copy of the same dialect, and the one a
        // scan reaches through a different door: the list writes it on a manual
        // add, the parser hands it to the probe. Two addresses for one board is
        // what this caught, and the link the reader shares is what it breaks.
        if (search.postUrl.isNotEmpty) {
          expect(
            _address(search.postUrl),
            _address(engine.postUrl),
            reason:
                '${engine.name} links posts to a page its parser does not serve',
          );
        }
        expect(
          suggestion.type.contains(BooruParserType.suggestion),
          isTrue,
          reason:
              '${engine.name} names ${suggestion.id} as its suggestion '
              'reader, and that parser does not read suggestions',
        );
      }
    });

    test('no two entries are the same dialect', () {
      // The server editor reads the engine back out of a saved row by its
      // parser pair, so two entries sharing one pair would let the same server
      // answer as two dialects. The Gelbooru rows are where that is easiest to
      // do by accident: they differ only in which revision they ask.
      final pairs = {
        for (final engine in booruEngines)
          (engine.searchParserId, engine.suggestionParserId),
      };
      expect(pairs, hasLength(booruEngines.length));

      final names = booruEngines.map((it) => it.name).toSet();
      expect(names, hasLength(booruEngines.length));
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
