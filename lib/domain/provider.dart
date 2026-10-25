import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/app_state/current_app_state_repo.dart';
import 'package:boorusphere/data/repository/booru/booru_repo.dart';
import 'package:boorusphere/data/repository/booru/provider.dart';
import 'package:boorusphere/data/repository/changelog/app_changelog_repo.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/user_download_repo.dart';
import 'package:boorusphere/data/repository/env/current_env_repo.dart';
import 'package:boorusphere/data/repository/fallback_box.dart';
import 'package:boorusphere/data/repository/favorite_post/entity/favorite_post.dart';
import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/data/repository/search_history/user_search_history.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/booru_tags_blocker_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/data/repository/version/app_version_repo.dart';
import 'package:boorusphere/domain/repository/app_state_repo.dart';
import 'package:boorusphere/domain/repository/changelog_repo.dart';
import 'package:boorusphere/domain/repository/downloads_repo.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/domain/repository/favorite_post_repo.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/domain/repository/search_history_repo.dart';
import 'package:boorusphere/domain/repository/server_data_repo.dart';
import 'package:boorusphere/domain/repository/settings_repo.dart';
import 'package:boorusphere/domain/repository/tags_blocker_repo.dart';
import 'package:boorusphere/domain/repository/version_repo.dart';
import 'package:boorusphere/pigeon/app_env.pi.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

@Riverpod(keepAlive: true)
EnvRepo envRepo(Ref ref) {
  throw UnimplementedError('must be initialized manually');
}

Future<EnvRepo> provideEnvRepo() async {
  return CurrentEnvRepo(env: await AppEnv().get());
}

/// The open box for [name], or the empty stand-in boot registered for it.
///
/// A box that failed to open stays closed, and `Hive.box` throws for it. That
/// throw would escape a provider read during a build, which leaves no way back
/// to the screen. The stand-in keeps the feature on its empty state for this
/// run; without one the failure surfaces as before.
Box<T> _boxOrFallback<T>(String name) {
  try {
    return Hive.box<T>(name);
  } on HiveError {
    final fallback = fallbackFor<T>(name);
    if (fallback == null) rethrow;
    return fallback;
  }
}

@riverpod
TagsBlockerRepo tagsBlockerRepo(Ref ref) {
  final box = _boxOrFallback<BooruTag>(BooruTagsBlockerRepo.boxKey);
  return BooruTagsBlockerRepo(box);
}

@riverpod
ImageboardRepo imageboardRepo(Ref ref, Server server) {
  return BooruRepo(
    parsers: ref.watch(booruParsersProvider),
    client: ref.watch(dioProvider),
    server: server,
    serverState: ref.watch(serverStateProvider.notifier),
  );
}

@riverpod
ChangelogRepo changelogRepo(Ref ref) {
  return AppChangelogRepo(bundle: rootBundle, client: ref.watch(dioProvider));
}

@riverpod
FavoritePostRepo favoritePostRepo(Ref ref) {
  final box = _boxOrFallback<FavoritePost>(UserFavoritePostRepo.key);
  return UserFavoritePostRepo(box);
}

@riverpod
SearchHistoryRepo searchHistoryRepo(Ref ref) {
  final box = _boxOrFallback<SearchHistory>(UserSearchHistoryRepo.key);
  return UserSearchHistoryRepo(box);
}

@riverpod
ServerRepo serverRepo(Ref ref) {
  return UserServerRepo(
    defaultServers: ref.watch(defaultServersProvider),
    box: _boxOrFallback<Server>(UserServerRepo.key),
  );
}

/// Kept alive for the session: the repository holds the values written while
/// the box is unavailable, and a fresh instance per read would drop them.
@Riverpod(keepAlive: true)
SettingsRepo settingsRepo(Ref ref) {
  // A box that failed to open must not throw here: this is read while the app
  // builds, and a throw would replace the UI with an error screen.
  return UserSettingsRepo(UserSettingsRepo.openBox());
}

@riverpod
VersionRepo versionRepo(Ref ref) {
  return AppVersionRepo(
    envRepo: ref.watch(envRepoProvider),
    client: ref.watch(dioProvider),
  );
}

@riverpod
DownloadsRepo downloadsRepo(Ref ref) {
  final entryBox = _boxOrFallback<DownloadEntry>(UserDownloadsRepo.entryKey);
  final progressBox = _boxOrFallback<DownloadProgress>(
    UserDownloadsRepo.progressKey,
  );
  return UserDownloadsRepo(entryBox: entryBox, progressBox: progressBox);
}

@riverpod
AppStateRepo appStateRepo(Ref ref) {
  final box = CurrentAppStateRepo.hiveBox();
  return CurrentAppStateRepo(box);
}
