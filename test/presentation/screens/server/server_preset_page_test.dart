import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/server_data_repo.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/first_run_view.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/screens/server/server_preset_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import '../../state/app_version_test.dart';

class _MockStackRouter extends Mock implements StackRouter {}

class _FakePageRouteInfo extends Fake implements PageRouteInfo {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakePageRouteInfo());
    registerFallbackValue(<PageRouteInfo>[]);
  });

  group('ServerPresetPage', () {
    testWidgets(
      'lists each bundled preset once even when saved servers carry edits, credentials or custom hosts',
      (tester) async {
        const safebooruPreset = Server(
          id: 'Safebooru',
          homepage: 'https://safebooru.org',
          searchUrl:
              'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}',
          tagSuggestionUrl: 'autocomplete.php?q={tag-part}',
          postUrl: 'index.php?page=post&s=view&id={post-id}',
          suggestionParserId: 'Autocomplete.json',
        );
        const gelbooruPreset = Server(
          id: 'Gelbooru',
          homepage: 'https://gelbooru.com',
          searchUrl:
              'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}&json=1',
          tagSuggestionUrl:
              'index.php?page=autocomplete2&term={tag-part}&type=tag_query&limit={post-limit}',
          postUrl: 'index.php?page=post&s=view&id={post-id}',
          suggestionParserId: 'Gelbooru.autocomplete',
          apiKeyUrl: 'https://gelbooru.com/index.php?page=account&s=options',
        );
        const danbooruPreset = Server(
          id: 'Danbooru',
          homepage: 'https://danbooru.donmai.us',
          searchUrl:
              'posts.json?tags={tags}&page={page-num}&limit={post-limit}',
          tagSuggestionUrl:
              'autocomplete.json?search[query]={tag-part}&search[type]=tag_query&limit={post-limit}',
          postUrl: 'posts/{post-id}',
          searchParserId: 'Danbooru.json',
          suggestionParserId: 'Danbooru.json',
        );

        final defaults = {
          safebooruPreset.key: safebooruPreset,
          gelbooruPreset.key: gelbooruPreset,
          danbooruPreset.key: danbooruPreset,
        };

        // Saved entries diverge from defaults via aliases, credentials, edited
        // endpoints, and a custom user-added server.
        final repo = _MemoryServerRepo(
          defaults: defaults,
          saved: [
            safebooruPreset.copyWith(alias: 'My Safebooru'),
            gelbooruPreset.copyWith(login: 'alice', apiKey: 'secret-key'),
            danbooruPreset.copyWith(
              searchUrl:
                  'posts.json?tags={tags}+rating:g&page={page-num}&limit={post-limit}',
            ),
            const Server(
              id: 'Custom Booru',
              homepage: 'https://custom.booru.test',
            ),
          ],
        );

        final router = _MockStackRouter();
        when(router.maybePop).thenAnswer((_) async => true);

        Server? picked;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              envRepoProvider.overrideWithValue(FakeEnvRepo()),
              settingsRepoProvider.overrideWithValue(UserSettingsRepo(null)),
              serverRepoProvider.overrideWithValue(repo),
              serverStateProvider.overrideWith(_SeededServerState.new),
            ],
            child: TranslationProvider(
              child: MaterialApp(
                home: StackRouterScope(
                  controller: router,
                  stateHash: 0,
                  child: ServerPresetPage(
                    onReturned: (server) => picked = server,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ListTile), findsNWidgets(defaults.length));
        expect(find.text('Safebooru'), findsOneWidget);
        expect(find.text('Gelbooru'), findsOneWidget);
        expect(find.text('Danbooru'), findsOneWidget);
        expect(find.text('My Safebooru'), findsNothing);
        expect(find.text('Custom Booru'), findsNothing);

        await tester.tap(find.text('Gelbooru'));
        await tester.pump();

        expect(picked, gelbooruPreset);
        expect(picked?.login, isEmpty);
        expect(picked?.apiKey, isEmpty);
        verify(router.maybePop).called(1);
      },
    );
  });

  group('FirstRunView preset browsing', () {
    testWidgets(
      'picking a preset through Browse presets adds the server and opens its timeline',
      (tester) async {
        final defaults = <String, Server>{
          for (var i = 1; i <= FirstRunView.presetLimit + 1; i++)
            '@booru-$i': Server(
              id: 'Booru $i',
              homepage: 'https://booru$i.example',
            ),
        };
        final repo = _MemoryServerRepo(defaults: defaults);
        final router = _MockStackRouter();
        when(() => router.push(any())).thenAnswer((_) async => null);
        when(() => router.replaceAll(any())).thenAnswer((_) async {});

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              envRepoProvider.overrideWithValue(FakeEnvRepo()),
              settingsRepoProvider.overrideWithValue(UserSettingsRepo(null)),
              serverRepoProvider.overrideWithValue(repo),
            ],
            child: TranslationProvider(
              child: MaterialApp(
                home: StackRouterScope(
                  controller: router,
                  stateHash: 0,
                  // Mirrors `HomeContent`, which drops `FirstRunView` as soon
                  // as the first server lands in `serverStateProvider`.
                  child: Consumer(
                    builder: (_, ref, _) =>
                        ref.watch(serverStateProvider).isEmpty
                        ? const Scaffold(body: FirstRunView())
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text(t.onboarding.browsePresets));
        await tester.pump();

        final pushed =
            verify(() => router.push(captureAny())).captured.single
                as ServerPresetRoute;
        expect(pushed.args?.onReturned, isNotNull);

        final sixth = defaults.values.last;
        pushed.args!.onReturned!(sixth);
        await tester.pump();
        await tester.pump();

        expect(repo.servers, [sixth]);
        final replaced =
            verify(() => router.replaceAll(captureAny())).captured.single
                as List<PageRouteInfo>;
        expect(replaced, [
          HomeRoute(session: SearchSession(serverId: sixth.id)),
        ]);
      },
    );
  });
}

class _SeededServerState extends ServerState {
  @override
  Iterable<Server> build() => ref.read(serverRepoProvider).servers;
}

class _MemoryServerRepo implements ServerRepo {
  _MemoryServerRepo({required this.defaults, List<Server> saved = const []})
    : _saved = {for (final s in saved) s.key: s};

  @override
  final Map<String, Server> defaults;

  final Map<String, Server> _saved;

  @override
  Iterable<Server> get servers => _saved.values.toList();

  @override
  Future<void> populate() async {}

  @override
  Future<void> add(Server data) async {
    _saved[data.key] = data;
  }

  @override
  Future<Server> edit(Server from, Server to) async {
    final updated = to.copyWith(id: from.id);
    _saved[from.key] = updated;
    return updated;
  }

  @override
  Future<void> remove(Server data) async {
    _saved.remove(data.key);
  }

  @override
  Future<void> reset() async {
    _saved
      ..clear()
      ..addAll(defaults);
  }

  @override
  Future<int?> import(String src) async => null;

  @override
  Future<BackupItem> export() async => const BackupItem('server', []);
}
