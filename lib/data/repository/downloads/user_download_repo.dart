import 'dart:io';

import 'package:boorusphere/data/repository/downloads/download_status_mapper.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/domain/repository/downloads_repo.dart';
import 'package:boorusphere/pigeon/storage_util.pi.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:boorusphere/utils/media_file.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;

class UserDownloadsRepo implements DownloadsRepo {
  UserDownloadsRepo({required this.entryBox, required this.progressBox});

  final Box<DownloadEntry> entryBox;
  final Box<DownloadProgress> progressBox;

  @override
  Iterable<DownloadEntry> getEntries() => entryBox.values;

  @override
  Iterable<DownloadProgress> getProgresses() => progressBox.values;

  @override
  Future<void> addEntry(DownloadEntry entry) async {
    await entryBox.put(entry.id, entry);
  }

  @override
  Future<void> updateProgress(DownloadProgress progress) async {
    await progressBox.put(progress.id, progress);
  }

  @override
  Future<void> removeEntry(String id) async {
    await entryBox.delete(id);
  }

  @override
  Future<void> removeProgress(String id) async {
    await progressBox.delete(id);
  }

  @override
  Future<void> clearEntries() async {
    // The plugin database is shared with the rest of the app and still holds
    // tasks this repo never recorded. Removing those would leave their owner
    // pointing at a row that no longer exists, so only the ids with an entry
    // here are removed.
    final owned = entryBox.keys.toSet();
    // The update APK is tracked here as well, and its entry is hidden from the
    // downloads list. APK tasks belong to the updater, which clears them on
    // its own (see `AppUpdater.clear`), so they are left alone here: removing
    // one would cancel an update the user cannot see.
    final kept = <String>{};
    try {
      final tasks = await FlutterDownloader.loadTasks();
      if (tasks != null) {
        final removable = <DownloadTask>[];
        for (final task in tasks) {
          if (!owned.contains(task.taskId)) {
            continue;
          }
          if (_isUpdaterTask(task.filename)) {
            kept.add(task.taskId);
            mainLog.d('Downloads: keeping ${task.taskId} (${task.filename})');
            continue;
          }
          removable.add(task);
        }
        await Future.wait(
          removable.map(
            (task) => FlutterDownloader.remove(
              taskId: task.taskId,
              shouldDeleteContent: false,
            ),
          ),
        );
      }
    } catch (e, stack) {
      mainLog.e('Downloads: failed to clear native tasks', e, stack);
    }

    // Clearing drops the records only: the files belong to the user, and
    // deleting one is an explicit action on its entry. The kept entries stay
    // recorded for the same reason their tasks were left in the plugin.
    await entryBox.deleteAll(entryBox.keys.where((key) => !kept.contains(key)));
  }

  @override
  Future<void> clearProgresses() async {
    await progressBox.deleteAll(progressBox.keys);
  }

  static const String entryKey = 'downloads';
  static const String progressKey = 'download_progresses';

  static Future<void> prepare() async {
    final entryBox = await Hive.openBox<DownloadEntry>(entryKey);
    final progressBox = await Hive.openBox<DownloadProgress>(progressKey);
    // The boxes above carry everything the rest of the app reads, while the
    // steps below only enrich them. A locked or corrupt native task database,
    // an unreachable storage path or a failing plugin channel has to leave a
    // bootable app behind instead of taking the whole start-up down.
    await _guard(
      'adapt stored download paths',
      () => _adaptEntryDest(entryBox),
    );
    await _guard(
      'import native download tasks',
      () => _migrateProgresses(progressBox),
    );
    await _guard(
      'initialize the download plugin',
      FlutterDownloader.initialize,
    );
    await _guard(
      'reconcile download progress',
      () => _syncProgresses(entryBox, progressBox),
    );
  }
}

/// Runs a start-up step that is optional for the app to work.
Future<void> _guard(String step, Future<void> Function() action) async {
  try {
    await action();
  } catch (e, stack) {
    mainLog.e('Downloads: failed to $step', e, stack);
  }
}

Future<void> _adaptEntryDest(Box<DownloadEntry> box) async {
  if (box.isEmpty) {
    return;
  }
  final downloadPath = await _downloadDir();
  final newEntries = <MapEntry<String, DownloadEntry>>[];
  for (final entry in box.values) {
    if (!path.isAbsolute(entry.dest)) {
      continue;
    }
    final newDest = path.relative(entry.dest, from: downloadPath);
    newEntries.add(MapEntry(entry.id, entry.copyWith(dest: newDest)));
  }
  await box.putAll(Map.fromEntries(newEntries));
}

/// Whether the task is the update APK. Those belong to the updater, which
/// clears them itself (see `AppUpdater.clear`).
bool _isUpdaterTask(String? fileName) {
  return (fileName ?? '').toLowerCase().endsWith('.apk');
}

Future<String> _downloadDir() async {
  final downloadPath = await StorageUtil().getDownloadPath();
  return path.join(downloadPath, 'Boorusphere');
}

/// Reconciles the persisted progress rows with the native task database.
///
/// Progress is otherwise only written by the downloader callback, which cannot
/// reach the app while its process is dead: a task that completed (or failed)
/// in the meantime would keep its last in-flight status on screen forever.
Future<void> _syncProgresses(
  Box<DownloadEntry> entryBox,
  Box<DownloadProgress> progressBox,
) async {
  final tasks = await FlutterDownloader.loadTasks();
  if (tasks == null) return;

  final byId = {for (final task in tasks) task.taskId: task};
  final updates = <String, DownloadProgress>{};
  final orphans = <String>[];
  final downloadDir = await _downloadDirOrNull();

  for (final progress in progressBox.values) {
    final task = byId.remove(progress.id);
    final entry = entryBox.get(progress.id);
    final hasEntry = entry != null;

    if (task == null) {
      // Terminal statuses are the app's own last word on the row, and without
      // a native task there is nothing left to compare them against: a
      // cancel, a failure and a file already on disk all stay as they are.
      if (progress.status.isDownloaded ||
          progress.status.isCanceled ||
          progress.status.isFailed) {
        continue;
      }

      // A row still reporting work the plugin no longer knows about: settle it
      // as failed while its entry is around, and drop it as an orphan once
      // nothing refers to it any more.
      if (progress.status.isPending ||
          progress.status.isDownloading ||
          progress.status.isPaused) {
        if (hasEntry) {
          updates[progress.id] = progress.copyWith(
            status: DownloadStatus.failed,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
        } else {
          orphans.add(progress.id);
        }
      }
      continue;
    }

    if (!hasEntry && isInFlightTask(task.status)) {
      // A task that outlived the process which enqueued it, with its entry
      // never written: the file is still on its way to disk, so the row stays
      // instead of being dropped as an orphan.
      mainLog.w(
        'Downloads: task ${progress.id} is still in flight without an entry',
      );
    }

    final status = downloadStatusOf(task.status);

    // A completed task is the one status the app did not witness: the worker
    // can finish while the process is dead, and the plugin reports COMPLETE
    // for any 200 body. The file is checked here the way the live completion
    // listener checks it, so a hotlink page cannot come back as a download.
    // Rows already claiming a download are left alone: re-reading every file
    // of the library on each boot would turn an unreachable folder into a
    // failed row for the whole list.
    if (status.isDownloaded &&
        !progress.status.isDownloaded &&
        entry != null &&
        !entry.post.isReserved &&
        !await _isCompletedFileUsable(downloadDir, entry)) {
      mainLog.w(
        'Downloads: ${entry.dest} is not media, marking the download as failed',
      );
      updates[progress.id] = progress.copyWith(
        status: DownloadStatus.failed,
        progress: task.progress,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      continue;
    }

    // The user's cancel is the app's last word on the row. The plugin can
    // still carry the task as ENQUEUED when the work was cancelled before a
    // Worker existed to report it, and reading that back as PENDING would undo
    // the cancel and take the retry action away.
    if (progress.status.isCanceled && !status.isDownloaded) {
      continue;
    }

    if (status != progress.status || task.progress != progress.progress) {
      updates[progress.id] = progress.copyWith(
        status: status,
        progress: task.progress,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  if (updates.isNotEmpty) await progressBox.putAll(updates);
  if (orphans.isNotEmpty) await progressBox.deleteAll(orphans);
}

/// Whether the file a completed task wrote is one the app can show, indexing
/// it when it is.
///
/// The file was written while the process was dead, so it is on disk but not
/// in the platform media database: without the scan the gallery would not see
/// it until something else scanned the folder.
///
/// A path the platform cannot resolve says nothing about the file, so the row
/// keeps the plugin's answer instead of being failed for it.
Future<bool> _isCompletedFileUsable(
  String? downloadDir,
  DownloadEntry entry,
) async {
  if (downloadDir == null) return true;

  final file = File(path.join(downloadDir, decodeComponentSafely(entry.dest)));
  if (!isMediaFile(file)) return false;

  try {
    await StorageUtil().scanMedia(file.path);
  } catch (e) {
    mainLog.e('Downloads: failed to scan ${entry.dest}', e);
  }
  return true;
}

Future<String?> _downloadDirOrNull() async {
  try {
    return await _downloadDir();
  } catch (e, stack) {
    mainLog.e('Downloads: failed to resolve the download folder', e, stack);
    return null;
  }
}

Future<void> _migrateProgresses(Box<DownloadProgress> box) async {
  const dbName = 'download_tasks.db';
  if (!(await sqflite.databaseExists(dbName))) {
    return;
  }

  sqflite.Database? db;
  try {
    db = await sqflite.openReadOnlyDatabase(dbName);
    final checkTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='task'",
    );
    if (checkTable.isEmpty) {
      return;
    }

    final table = await db.query('task');
    final tasks = <MapEntry<String, DownloadProgress>>[];
    for (var x in table) {
      String id = x['task_id'].toString();
      if (box.keys.contains(id)) {
        continue;
      }

      int prog = int.tryParse(x['progress'].toString()) ?? 0;
      int timestamp = int.tryParse(x['time_created'].toString()) ?? 0;
      int status = int.tryParse(x['status'].toString()) ?? 0;
      final progress = DownloadProgress(
        id: id,
        status: switch (status) {
          1 => DownloadStatus.pending,
          2 => DownloadStatus.downloading,
          3 => DownloadStatus.downloaded,
          4 => DownloadStatus.failed,
          5 => DownloadStatus.canceled,
          6 => DownloadStatus.paused,
          _ => DownloadStatus.empty,
        },
        progress: prog,
        timestamp: timestamp,
      );
      tasks.add(MapEntry(id, progress));
    }

    if (tasks.isNotEmpty) {
      await box.putAll(Map.fromEntries(tasks));
    }
  } finally {
    // Covers the open itself as well: a handle that was already created when
    // a later call throws still gets closed.
    await db?.close();
  }
}
