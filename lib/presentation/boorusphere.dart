import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/downloads/download_sidecar.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/settings_repo.dart';
import 'package:boorusphere/presentation/i18n/helper.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_boot_state.dart';
import 'package:boorusphere/presentation/provider/app_lock/app_lock_state.dart';
import 'package:boorusphere/presentation/provider/app_updater.dart';
import 'package:boorusphere/presentation/provider/data_backup/periodic_backup_runner.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/download/downloader.dart';
import 'package:boorusphere/presentation/provider/download/flutter_downloader_handle.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/routes/app_route_observer.dart';
import 'package:boorusphere/presentation/routes/app_router.dart';
import 'package:boorusphere/presentation/routes/route_visibility.dart';
import 'package:boorusphere/presentation/screens/app_lock/app_lock_screen.dart';
import 'package:boorusphere/presentation/widgets/app_theme_builder.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/utils/http/overrides.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:boorusphere/utils/secure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class Boorusphere extends HookConsumerWidget {
  const Boorusphere({super.key});

  /// Runs the work that has to finish before the timeline is shown.
  ///
  /// [onCompleted] always runs: the boot gate waits on it, so a failure that
  /// skipped it would leave the spinner on screen for the rest of the session.
  /// The failure is handed back instead, so the app opens with an empty server
  /// list and a way to try again.
  Future<void> initializeAsyncStates(
    WidgetRef ref, {
    required void Function(Object? failure) onCompleted,
  }) async {
    Object? failure;
    try {
      await ref.read(serverStateProvider.notifier).populate();
    } catch (e, stack) {
      mainLog.e('Boot: failed to load the server list', e, stack);
      failure = e;
    }

    // The settings box can fail on its own while the server list loads fine.
    // The app then runs on defaults, so the failure is reported through the
    // same card instead of resetting the user's preferences without a word.
    if (!ref.read(settingsRepoProvider).isPersistent) {
      failure ??= const SettingsUnavailableException();
    }

    try {
      final envRepo = ref.read(envRepoProvider);
      final appStateRepo = ref.read(appStateRepoProvider);
      final updater = ref.read(appUpdaterProvider.notifier);
      if (envRepo.appVersion.isNewerThan(appStateRepo.version)) {
        await updater.clear();
      }
      // The plugin keeps its task across a restart. Reattaching to it is what
      // keeps Install on offer instead of deleting a finished APK on the next
      // tap of Download.
      await updater.restore();
    } catch (e, stack) {
      mainLog.e('Boot: failed to restore the update state', e, stack);
    }

    onCompleted(failure);
  }

  /// Reports a boot failure the app survived. The server list stays empty, and
  /// the action retries the load that failed.
  void _reportBootFailure(
    BuildContext context,
    WidgetRef ref,
    GlobalKey<ScaffoldMessengerState> messenger,
  ) {
    final t = TranslationProvider.of(context).translations;
    final messengerState = messenger.currentState;
    if (messengerState == null) return;

    messengerState.hideCurrentSnackBar();
    showToastOn(
      messengerState,
      t.error.unknown,
      actionLabel: t.retry,
      onAction: () {
        ref.read(serverStateProvider.notifier).populate().catchError((
          Object error,
          StackTrace stack,
        ) {
          mainLog.e('Boot: retrying the server list failed', error, stack);
          if (!context.mounted) return;
          _reportBootFailure(context, ref, messenger);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(uiSettingStateProvider.select((ui) => ui.locale));
    final theme = ref.watch(
      uiSettingStateProvider.select((ui) => ui.themeMode),
    );
    final isMidnight = ref.watch(
      uiSettingStateProvider.select((ui) => ui.midnightMode),
    );
    final flagSecure = ref.watch(
      uiSettingStateProvider.select((ui) => ui.flagSecure),
    );
    final appLock = ref.watch(appLockProvider);
    final backDispatcher = _LockAwareBackButtonDispatcher(
      isLocked: () => ref.read(appLockProvider).isLocked,
    );
    final envRepo = ref.watch(envRepoProvider);
    final cookieJar = ref.watch(cookieJarProvider);
    final router = useMemoized(AppRouter.new);
    final messengerKey = useMemoized(
      GlobalKey<ScaffoldMessengerState>.new,
      const [],
    );
    final initialized = useState(false);
    final sdkVersion = envRepo.sdkVersion;

    // All hooks must run unconditionally on every build (`flutter_hooks`
    // requires a stable hook count). Don't reorder these or insert hooks below
    // the early `if (!initialized.value) return` guard.

    useEffect(() {
      initializeAsyncStates(
        ref,
        onCompleted: (failure) {
          // Whatever the outcome, the server list is settled now: the start
          // page may open the timeline.
          ref.read(appBootStateProvider.notifier).complete();
          initialized.value = true;
          if (failure != null) {
            _reportBootFailure(context, ref, messengerKey);
          }
          // The interval check reads stored settings, so it waits for the
          // boxes to be open instead of running during the first frame.
          unawaited(ref.read(periodicBackupRunnerProvider).maybeRun());
        },
      );
      return null;
    }, const []);

    // Nothing runs while the app is in the background, so every return to the
    // foreground is a chance for a backup that came due to catch up. The same
    // transitions are what arm and fire the app lock.
    useEffect(() {
      final lock = ref.read(appLockProvider.notifier);
      final listener = AppLifecycleListener(
        onPause: lock.onAppPaused,
        onResume: () {
          lock.onAppResumed();
          unawaited(ref.read(periodicBackupRunnerProvider).maybeRun());
        },
      );
      return listener.dispose;
    }, const []);

    useEffect(() {
      HttpOverrides.global = CustomHttpOverrides(cookieJar: cookieJar);
      return () {
        HttpOverrides.global = null;
      };
    }, [cookieJar]);

    useEffect(() {
      LocaleHelper.update(locale);
      return null;
    }, [locale]);

    useEffect(() {
      unawaited(SecureScreen.setFlagSecure(flagSecure));
      return null;
    }, [flagSecure]);

    useEffect(() {
      // `FlutterDownloaderHandle.listen` returns void and the underlying
      // ReceivePort is torn down via `ref.onDispose(handle.dispose)` in the
      // provider, so there's nothing to clean up here.
      ref.read(downloaderHandleProvider).listen((progress) async {
        final progressState = ref.read(downloadProgressStateProvider.notifier);

        if (!progress.status.isDownloaded) {
          await progressState.update(progress);
          return;
        }

        // The plugin reports COMPLETE for any HTTP 200 body, so a hotlink
        // page, an empty file or a truncated transfer arrives here looking
        // like a finished download. The bytes are checked before the row is
        // allowed to claim success.
        final entry = ref.read(downloadEntryStateProvider).getById(progress.id);
        // A task without an entry was cleared or cancelled while it was still
        // running: a row for it would be one the Downloads list can never show.
        if (entry.id.isEmpty) return;

        // The update APK is written to the cache folder, not to the shared
        // one, and its entry resolves against the shared folder. Validating it
        // there would fail every update right after it arrived.
        if (!entry.post.isReserved) {
          final storage = ref.read(sharedStorageHandleProvider);

          Future<void> markFailed() async {
            await progressState.update(
              DownloadProgress(
                id: progress.id,
                status: DownloadStatus.failed,
                progress: progress.progress,
                timestamp: progress.timestamp,
              ),
            );
          }

          if (!storage.isValidMedia(entry.dest)) {
            mainLog.w(
              'Boorusphere: ${entry.dest} is not media, '
              'marking the download as failed',
            );
            await markFailed();
            return;
          }

          // A body that ends before its last byte still looks complete to the
          // worker, so a truncated transfer only shows up when its size is
          // compared with the length the server reports. A host that reports
          // none yields no expectation and keeps the check above as its only
          // guard.
          final expectedSize = await ref
              .read(downloaderProvider)
              .expectedSizeOf(progress.id);
          final actualSize = storage.fileSize(entry.dest);
          if (expectedSize != null &&
              actualSize != null &&
              actualSize != expectedSize) {
            mainLog.w(
              'Boorusphere: ${entry.dest} has $actualSize bytes, '
              'the server reports $expectedSize, marking the download as '
              'failed',
            );
            await markFailed();
            return;
          }

          await storage.rescanFile(entry.dest);
        }

        // The finished file now has a record that survives the entry list:
        // deleting the record does not delete the file, so the metadata is
        // what still ties a file on disk to the post it came from. App-owned
        // rows are skipped inside the helper.
        await writeDownloadSidecar(
          root: ref.read(sharedStorageHandleProvider).path,
          entry: entry,
        );

        await progressState.update(progress);
      });
      return null;
    }, const []);

    useEffect(() {
      if (sdkVersion > 28) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      return null;
    }, [sdkVersion]);

    return AppThemeBuilder(
      builder: (context, appTheme) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        title: 'Boorusphere',
        theme: appTheme.day,
        darkTheme: isMidnight ? appTheme.midnight : appTheme.night,
        themeMode: theme,
        routerConfig: RouterConfig<UrlState>(
          routeInformationProvider: router.routeInfoProvider(),
          routeInformationParser: router.defaultRouteParser(),
          routerDelegate: router.delegate(
            navigatorObservers: () => [AppRouteObserver(ref), appRouteObserver],
          ),
          // Back must not reach the navigator under the lock cover: it would
          // pop pages the user cannot see, or close the app. The builder sits
          // above the Router, so a BackButtonListener cannot be used here.
          backButtonDispatcher: backDispatcher,
        ),
        locale: TranslationProvider.of(context).locale.digestedFlutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // The boot gate lives inside the app, so the frame that waits for
        // the servers carries the theme instead of a blank window.
        builder: (context, child) {
          final content = initialized.value
              ? (child ?? const SizedBox.shrink())
              : const _BootScreen();

          // The content keeps the same slot in the tree whether the cover is
          // up or not: only the properties around it change. Wrapping it in a
          // Stack on lock and unwrapping it on unlock would tear the navigator
          // down on every unlock, losing the page the user left and leaving a
          // Scaffold from the discarded subtree registered with the messenger,
          // which then throws on the next snackbar.
          //
          // The cover paints over every pixel; the tree beneath it is neither
          // reachable by touch nor read by a screen reader while it is up.
          return Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  excluding: appLock.isLocked,
                  child: IgnorePointer(
                    ignoring: appLock.isLocked,
                    child: content,
                  ),
                ),
              ),
              if (appLock.isLocked)
                const Positioned.fill(child: AppLockScreen()),
            ],
          );
        },
      ),
    );
  }
}

/// First frame: the themed surface with a single progress ring, so the gap
/// between the native launch screen and the timeline is not a blank window.
class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

/// Swallows the back gesture while the lock cover is up.
///
/// The root dispatcher is the only place Android back can be intercepted from:
/// the app builder sits above the Router, so a [BackButtonListener] there has
/// no [Router] to register with. Reading the state when the press arrives, not
/// when the dispatcher is built, keeps a stale closure from answering.
class _LockAwareBackButtonDispatcher extends RootBackButtonDispatcher {
  _LockAwareBackButtonDispatcher({required this.isLocked});

  final bool Function() isLocked;

  @override
  Future<bool> didPopRoute() async {
    if (isLocked()) return true;
    return super.didPopRoute();
  }
}

// Convert slang locale to flutter locale
extension on AppLocale {
  Locale get digestedFlutterLocale {
    if (this == AppLocale.uwu) {
      return AppLocale.en.flutterLocale;
    }

    // Return the actual locale
    return flutterLocale;
  }
}
