import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/favorite_post_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// In-memory stand-in for the Hive box, so a batch write can be counted.
class _MemoryFavoriteRepo implements FavoritePostRepo {
  final _byKey = <String, Post>{};

  @override
  Iterable<Post> get() => _byKey.values.toList();

  @override
  Future<void> save(Post post) async =>
      _byKey['${post.id}@${post.serverId}'] = post;

  @override
  Future<void> remove(Post post) async =>
      _byKey.remove('${post.id}@${post.serverId}');

  @override
  Future<void> clear() async => _byKey.clear();

  @override
  Future<int?> import(String src) async => 0;

  @override
  Future<BackupItem> export() async => const BackupItem('favorites', []);
}

void main() {
  testWidgets('a batch favorite saves every selected post', (tester) async {
    final repo = _MemoryFavoriteRepo();
    final posts = [for (var i = 1; i <= 3; i++) Post(id: i, serverId: 'srv')];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [favoritePostRepoProvider.overrideWithValue(repo)],
        // The grid never watches the favorite state, so this reproduces the
        // home screen: the provider is only ever read from the action bar.
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () async {
                final favorites = ref.read(favoritePostStateProvider.notifier);
                final added = posts
                    .where((it) => !favorites.isFavorite(it))
                    .toList();
                for (final post in added) {
                  await ref.read(favoritePostStateProvider.notifier).save(post);
                }
              },
              child: const Text('favorite'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('favorite'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.get().length, posts.length);
  });

  testWidgets('an undo captured in a page scope still works once it closes', (
    tester,
  ) async {
    // The batch-favorite undo is shown by the root messenger, which outlives
    // the Home page. The notifier read inside the page scope has to keep
    // working after that scope is gone, or the undo silently does nothing.
    final repo = _MemoryFavoriteRepo();
    const post = Post(id: 1, serverId: 'srv');
    final pageOpen = ValueNotifier(true);
    FavoritePostState? captured;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [favoritePostRepoProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: pageOpen,
            builder: (context, open, _) => open
                ? ProviderScope(
                    overrides: [
                      searchSessionProvider.overrideWith(
                        (ref) => const SearchSession(serverId: 'srv'),
                      ),
                    ],
                    child: Consumer(
                      builder: (context, ref, _) => ElevatedButton(
                        onPressed: () {
                          captured = ref.read(
                            favoritePostStateProvider.notifier,
                          );
                        },
                        child: const Text('favorite'),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('favorite'));
    pageOpen.value = false;
    await tester.pump();

    final favorites = captured!;
    await favorites.save(post);
    expect(favorites.isFavorite(post), isTrue);

    await favorites.remove(post);
    expect(favorites.isFavorite(post), isFalse);
    expect(repo.get(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
