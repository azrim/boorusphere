import 'dart:io';

import 'package:boorusphere/constant/app.dart';
import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/download_status_mapper.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_updater.g.dart';

/// File name the updater writes inside its cache folder for [version].
String updateApkFileName(AppVersion version) {
  return 'boorusphere-$version-$kAppArch.apk';
}

/// Kept alive for the session: the task id has to survive navigation between
/// About and the drawer, and every method reads [Ref] after awaits, which an
/// auto-disposed element cannot survive.
@Riverpod(keepAlive: true)
class AppUpdater extends _$AppUpdater {
  /// Folder the APK is enqueued into, resolved on [start].
  String _savedDir = '';

  /// Whether [start] is still between its first await and the task it
  /// enqueued. A second tap in that gap would clear the task the first one is
  /// already creating.
  bool _starting = false;

  /// Native task behind the update APK, or an empty string when there is none.
  ///
  /// This is provider state instead of a field on a long-lived object: the
  /// About button and the drawer footer watch it, and a field mutation would
  /// never notify either of them.
  @override
  String build() => '';

  Future<List<DownloadTask>> _apkTasks() async {
    final tasks = await FlutterDownloader.loadTasksWithRawQuery(
      query: 'SELECT * FROM task WHERE file_name LIKE \'%.apk\'',
    );
    return tasks ?? const [];
  }

  /// Picks up the update task the plugin kept across a restart.
  ///
  /// Without this the button reads "Download" after every start even when the
  /// APK is already on disk, and a tap would delete that file and start over.
  Future<void> restore() async {
    try {
      final tasks = await _apkTasks();
      if (tasks.isEmpty) {
        state = '';
        return;
      }

      final latest = tasks.reduce(
        (a, b) => a.timeCreated >= b.timeCreated ? a : b,
      );
      state = latest.taskId;

      final fileName = latest.filename;
      if (fileName == null || fileName.isEmpty) return;

      // The completion listener and the boot reconciliation both need a record
      // for a task that outlived the UI that started it. The record is marked
      // app-owned: the APK lives in the cache folder, so the shared-folder
      // media checks must skip it and the downloads list must hide it.
      final entry = ref.read(downloadEntryStateProvider).getById(latest.taskId);
      if (entry.id.isEmpty) {
        await ref
            .read(downloadEntryStateProvider.notifier)
            .add(
              DownloadEntry(
                id: latest.taskId,
                post: Post.appReserved,
                dest: fileName,
              ),
            );
      } else if (!entry.post.isReserved) {
        // Rows recorded before the updater marked its record this way would be
        // validated against the shared folder and failed on arrival.
        await ref
            .read(downloadEntryStateProvider.notifier)
            .update(entry.id, entry.copyWith(post: Post.appReserved));
      }

      final progress = ref
          .read(downloadProgressStateProvider)
          .getById(latest.taskId);
      if (progress.status.isEmpty) {
        await ref
            .read(downloadProgressStateProvider.notifier)
            .update(
              DownloadProgress(
                id: latest.taskId,
                status: downloadStatusOf(latest.status),
                progress: latest.progress,
                timestamp: latest.timeCreated,
              ),
            );
      }
    } catch (e, stack) {
      mainLog.e('AppUpdater: failed to restore the update task', e, stack);
    }
  }

  /// Removes every update task together with its file.
  Future<void> clear() async {
    state = '';
    try {
      final tasks = await _apkTasks();
      for (final task in tasks) {
        await ref.read(downloadEntryStateProvider.notifier).remove(task.taskId);
        await FlutterDownloader.remove(
          taskId: task.taskId,
          shouldDeleteContent: true,
        );
      }
    } catch (e, stack) {
      mainLog.e('AppUpdater: failed to clear the update task', e, stack);
    }
  }

  Future<void> start(AppVersion version) async {
    // A second tap while the task is still queued would delete the bytes the
    // first one has written and enqueue the same file again.
    if (_starting) return;
    final current = ref.read(downloadProgressStateProvider).getById(state);
    if (current.status.isPending || current.status.isDownloading) return;

    _starting = true;
    try {
      await clear();
      final fileName = updateApkFileName(version);
      final url = version.apkUrl;

      // The APK lives in its own folder inside the cache, which the app's file
      // provider exposes so the package installer can read the file.
      final cacheDir = await getExternalCacheDirectories();
      final rootDir = cacheDir?.firstOrNull ?? await getTemporaryDirectory();
      final saveDir = Directory(path.join(rootDir.path, 'apk'));
      _savedDir = saveDir.path;

      // Create directory if it doesn't exist
      if (!saveDir.existsSync()) {
        try {
          saveDir.createSync(recursive: true);
        } catch (e) {
          mainLog.e('AppUpdater: Failed to create cache dir', e);
        }
      }

      // Delete existing APK if present
      final apk = File(path.join(_savedDir, fileName));
      if (apk.existsSync()) {
        try {
          apk.deleteSync();
        } catch (e) {
          mainLog.e('AppUpdater: Failed to delete old apk', e);
        }
      }

      final versionRepo = ref.read(versionRepoProvider);
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        fileName: fileName,
        savedDir: _savedDir,
        showNotification: true,
        openFileFromNotification: true,
        headers: HeadersFactory.builder()
            .setUserAgent(versionRepo.current)
            .build(),
      );
      if (taskId == null) return;

      await ref
          .read(downloadEntryStateProvider.notifier)
          .add(
            DownloadEntry(id: taskId, post: Post.appReserved, dest: fileName),
          );
      // The plugin never reports ENQUEUED to Dart, so without this row the
      // About button would keep offering Download while the task waits for a
      // network, and boot reconciliation would have nothing to settle.
      await ref
          .read(downloadProgressStateProvider.notifier)
          .update(
            DownloadProgress(
              id: taskId,
              status: DownloadStatus.pending,
              progress: 0,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      // Published last: the button only sees the id once its row is readable.
      state = taskId;
    } catch (e, stack) {
      mainLog.e('AppUpdater: failed to start the update download', e, stack);
    } finally {
      _starting = false;
    }
  }

  Future<void> install(AppVersion version) async {
    final taskId = state;
    if (taskId.isEmpty) return;

    final entry = ref.read(downloadEntryStateProvider).getById(taskId);
    // A task restored from a previous release must not install in place of the
    // version the About page is offering.
    if (entry.dest != updateApkFileName(version)) return;

    await FlutterDownloader.open(taskId: taskId);
  }
}

/// Progress of the update task, or an empty record while there is none.
@riverpod
DownloadProgress appUpdateProgress(Ref ref) {
  final id = ref.watch(appUpdaterProvider);
  // Scoped to the update's own task: watching the whole list woke the drawer
  // footer on every percent tick of every other download.
  return ref.watch(
    downloadProgressStateProvider.select((it) => it.getById(id)),
  );
}
