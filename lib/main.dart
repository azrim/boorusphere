import 'dart:io';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/app_state/current_app_state_repo.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/data/repository/downloads/user_download_repo.dart';
import 'package:boorusphere/data/repository/env/fallback_env_repo.dart';
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
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/presentation/boorusphere.dart';
import 'package:boorusphere/presentation/i18n/helper.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/entity/download_quality.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/utils/device_workarounds.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  setupLogger();
  WidgetsFlutterBinding.ensureInitialized();

  // Opt into the highest available refresh rate on Android. By default Flutter
  // apps run at 60 Hz even on 90/120 Hz displays; this single call delivers a
  // large perceived smoothness uplift on modern Pixel/Samsung devices and is
  // the highest-ROI fix in the UI audit. Failures are non-fatal because some
  // OEM Androids report unusable display modes.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {
      // Ignored: not all OEMs honor the API; we fall back to the default mode.
    }
  }

  await Hive.initFlutter();

  Hive.registerAdapter(ServerAdapter());
  Hive.registerAdapter(BooruTagAdapter());
  Hive.registerAdapter(SearchHistoryAdapter());
  Hive.registerAdapter(PostAdapter());
  Hive.registerAdapter(DownloadEntryAdapter());
  Hive.registerAdapter(FavoritePostAdapter());
  Hive.registerAdapter(BooruRatingAdapter());
  Hive.registerAdapter(DownloadQualityAdapter());
  Hive.registerAdapter(DownloadStatusAdapter());
  Hive.registerAdapter(DownloadProgressAdapter());

  await Future.wait([
    _prepare(
      'servers',
      UserServerRepo.prepare,
      fallback: () => openFallbackBox<Server>(UserServerRepo.key),
    ),
    _prepare(
      'blocked tags',
      BooruTagsBlockerRepo.prepare,
      fallback: () => openFallbackBox<BooruTag>(BooruTagsBlockerRepo.boxKey),
    ),
    _prepare(
      'favorites',
      UserFavoritePostRepo.prepare,
      fallback: () => openFallbackBox<FavoritePost>(UserFavoritePostRepo.key),
    ),
    _prepare(
      'search history',
      UserSearchHistoryRepo.prepare,
      fallback: () => openFallbackBox<SearchHistory>(UserSearchHistoryRepo.key),
    ),
    // The settings box is left without a stand-in: the repository reads a
    // missing box as "not persistent" and reports that through the boot card,
    // which a stand-in would silence.
    _prepare('settings', UserSettingsRepo.prepare),
    _prepare(
      'downloads',
      UserDownloadsRepo.prepare,
      fallback: _openDownloadFallbacks,
    ),
    _prepare('app state', CurrentAppStateRepo.prepare),
  ]);

  LocaleHelper.setupPluralResolver();
  DeviceWorkarounds.apply();

  // Each of these is overridden into the widget tree below, so a failure would
  // reject the whole list and leave the process without a UI. A fallback keeps
  // the one feature degraded instead of taking the boot down.
  final results = await Future.wait<Object>([
    _bootstrap(
      'the shared download folder',
      provideSharedStorageHandle,
      _fallbackSharedStorageHandle,
    ),
    _bootstrap('the cookie store', provideCookieJar, () async => CookieJar()),
    _bootstrap(
      'the bundled server presets',
      provideDefaultServers,
      () async => <String, Server>{},
    ),
    _bootstrap(
      'the platform environment',
      provideEnvRepo,
      () async => const FallbackEnvRepo(),
    ),
  ]);

  runApp(
    ProviderScope(
      overrides: [
        sharedStorageHandleProvider.overrideWithValue(
          results[0] as SharedStorageHandle,
        ),
        cookieJarProvider.overrideWithValue(results[1] as CookieJar),
        defaultServersProvider.overrideWithValue(
          results[2] as Map<String, Server>,
        ),
        envRepoProvider.overrideWithValue(results[3] as EnvRepo),
      ],
      child: TranslationProvider(child: const Boorusphere()),
    ),
  );
}

/// Runs a repository's start-up work without letting a failure stop the app.
///
/// A box that cannot be opened only breaks the feature that owns it, while a
/// rejected [Future.wait] would take the whole boot down and leave the process
/// without a UI, on this launch and on every launch after it. [fallback] then
/// opens a stand-in box, so the providers that read this one answer with an
/// empty box instead of throwing.
Future<void> _prepare(
  String name,
  Future<void> Function() prepare, {
  Future<void> Function()? fallback,
}) async {
  try {
    await prepare();
  } catch (e, stack) {
    mainLog.e('Boot: failed to prepare $name', e, stack);
    if (fallback == null) return;
    try {
      await fallback();
    } catch (e, stack) {
      mainLog.e('Boot: failed to open a stand-in for $name', e, stack);
    }
  }
}

/// Opens a stand-in for both boxes the downloads feature reads, since boot
/// opens them as a pair.
Future<void> _openDownloadFallbacks() async {
  await openFallbackBox<DownloadEntry>(UserDownloadsRepo.entryKey);
  await openFallbackBox<DownloadProgress>(UserDownloadsRepo.progressKey);
}

/// Resolves a boot dependency, and answers with [fallback] when it fails.
Future<T> _bootstrap<T>(
  String name,
  Future<T> Function() provide,
  Future<T> Function() fallback,
) async {
  try {
    return await provide();
  } catch (e, stack) {
    mainLog.e('Boot: failed to provide $name', e, stack);
    final value = await fallback();
    mainLog.w('Boot: $name falls back to a degraded value for this run');
    return value;
  }
}

/// The download folder used when the platform storage path cannot be resolved.
///
/// The cache directory is writable without a storage permission, so downloads
/// keep working for this run; the system may clear it, and unlike the shared
/// folder its files are not indexed for other apps.
Future<SharedStorageHandle> _fallbackSharedStorageHandle() async {
  String downloadPath;
  try {
    downloadPath = (await getTemporaryDirectory()).path;
  } catch (e, stack) {
    mainLog.e('Boot: failed to resolve the cache directory', e, stack);
    downloadPath = Directory.systemTemp.path;
  }
  return SharedStorageHandle(downloadPath: downloadPath);
}
