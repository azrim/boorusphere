import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/favorite_post_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
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
  Future<void> import(String src) async {}

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
}
