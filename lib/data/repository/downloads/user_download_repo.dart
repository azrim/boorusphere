import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/download_sidecar.dart';
import 'package:boorusphere/data/repository/downloads/download_status_mapper.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/domain/repository/downloads_repo.dart';
import 'package:boorusphere/pigeon/storage_util.pi.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:boorusphere/utils/media_file.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;

class UserDownloadsRepo implements DownloadsRepo {
  UserDownloadsRepo({
    required this.entryBox,
    required this.progressBox,
    Future<String?> Function()? downloadDir,
    Future<Set<String>> Function()? nativeTaskIds,
  }) : _downloadDir = downloadDir ?? _downloadDirOrNull,
       _nativeTaskIds = nativeTaskIds ?? _loadNativeTaskIds;

  final Box<DownloadEntry> entryBox;
  final Box<DownloadProgress> progressBox;

  /// Where the media files live, resolved for an import. Injected so a test
  /// can point at a temporary folder instead of the platform storage.
  final Future<String?> Function() _downloadDir;

  /// Ids of the native tasks this install still tracks. A restored record
  /// must not replace one of them: the running task owns its row.
  final Future<Set<String>> Function() _nativeTaskIds;

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
  Future<Set<String>> clearEntries() async {
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
    return kept;
  }

  @override
  Future<void> clearProgresses() async {
    await progressBox.deleteAll(progressBox.keys);
  }

  @override
  Future<BackupItem> export() async {
    final entries = <Map<String, Object?>>[];
    final exportedIds = <String>{};
    for (final entry in entryBox.values) {
      // The updater APK is app bookkeeping, not a download the user made, and
      // its task belongs to the updater on this device.
      if (entry.id.isEmpty || entry.post.isReserved) continue;
      exportedIds.add(entry.id);
      entries.add({
        'id': entry.id,
        'post': entry.post.toJson(),
        'dest': entry.dest,
      });
    }

    final progresses = [
      for (final progress in progressBox.values)
        if (exportedIds.contains(progress.id))
          {
            'id': progress.id,
            'status': progress.status.name,
            'progress': progress.progress,
            'timestamp': progress.timestamp,
          },
    ];

    return BackupItem(entryKey, {
      'schema': backupSchema,
      'entries': entries,
      'progresses': progresses,
    });
  }

  @override
  Future<int?> import(String src) async {
    final Object? data;
    try {
      data = jsonDecode(src);
    } catch (e) {
      // Not a download payload this build can read; keep the stored records.
      return null;
    }
    if (data is! Map || data['schema'] != backupSchema) return null;

    final rawEntries = data['entries'];
    if (rawEntries is! List) return null;

    // The archive named no records. The list is merged rather than replaced,
    // so there is nothing to write and nothing to remove.
    if (rawEntries.isEmpty) return 0;

    // Every record is decoded before a box is touched, so one malformed entry
    // leaves the current download list as it is.
    final restored = <String, DownloadEntry>{};
    for (final raw in rawEntries) {
      if (raw is! Map) continue;
      final id = raw['id'];
      final dest = raw['dest'];
      final post = raw['post'];
      if (id is! String || id.isEmpty || dest is! String || post is! Map) {
        continue;
      }

      final normalizedDest = _restoreDest(dest);
      if (normalizedDest == null) continue;

      final Post decoded;
      try {
        decoded = Post.fromJson(Map<String, dynamic>.from(post));
      } catch (_) {
        continue;
      }
      if (decoded.isReserved) continue;

      restored[id] = DownloadEntry(id: id, post: decoded, dest: normalizedDest);
    }
    // A payload whose records none of which could be read is not an empty
    // one: it leaves the stored records alone.
    if (restored.isEmpty) return null;

    // A native task that is still around keeps its own record: writing the
    // archived one over it would leave the running task pointing at a row the
    // plugin never wrote.
    final busy = await _nativeTaskIds();
    restored.removeWhere((id, _) => busy.contains(id));
    // Every record the archive carried belongs to a task that is still
    // running here, so none of them may be written. That is not a failed
    // import, only an empty one.
    if (restored.isEmpty) return 0;

    final progressById = <String, Map>{};
    if (data['progresses'] case final List rawProgresses) {
      for (final raw in rawProgresses) {
        if (raw is! Map) continue;
        final id = raw['id'];
        if (id is String) progressById[id] = raw;
      }
    }

    final downloadDir = await _downloadDir();
    final entries = <String, DownloadEntry>{};
    final progresses = <String, DownloadProgress>{};
    for (final entry in restored.values) {
      final archived = progressById[entry.id];
      final timestamp = _restoredTimestamp(archived?['timestamp']);

      final root = downloadDir;
      final file = root == null ? null : File(path.join(root, entry.dest));
      final present = file?.existsSync() ?? false;
      final usable = present && isMediaFile(file!);
      if (usable) {
        // The file is already on this device, so the record is the same one
        // the live completion listener would have written.
        entries[entry.id] = entry;
        progresses[entry.id] = DownloadProgress(
          id: entry.id,
          status: DownloadStatus.downloaded,
          progress: 100,
          timestamp: timestamp,
        );
        await writeDownloadSidecar(root: root!, entry: entry);
        continue;
      }

      // A file that is there but cannot be opened must not stay downloaded: the
      // row would offer to open bytes that no viewer can read. A missing file
      // keeps the archived answer, which is what turns a downloaded record
      // into the "No file" row that offers a redownload.
      final status = present
          ? DownloadStatus.failed
          : _restoredStatus(archived?['status']);
      entries[entry.id] = entry;
      progresses[entry.id] = DownloadProgress(
        id: entry.id,
        status: status,
        progress: _restoredProgress(archived?['progress'], status),
        timestamp: timestamp,
      );
    }

    await entryBox.putAll(entries);
    await progressBox.putAll(progresses);
    return entries.length;
  }

  /// Schema of the download payload inside a backup.
  ///
  /// A restore may be read by a build that predates the current shape, so the
  /// number is checked before any record is trusted.
  static const int backupSchema = 1;

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
    if (path.isAbsolute(entry.dest)) {
      final newDest = path.relative(entry.dest, from: downloadPath);
      newEntries.add(MapEntry(entry.id, entry.copyWith(dest: newDest)));
      continue;
    }

    // An archive written by an older build stored the path percent-encoded,
    // while every reader now joins it literally. The path is decoded once,
    // only when the literal path has no file behind it and the decoded one
    // does: a real `%` in a folder name keeps pointing at its own file.
    if (!entry.dest.contains('%')) continue;
    final decoded = _restoreDest(decodeComponentSafely(entry.dest));
    if (decoded == null || decoded == entry.dest) continue;
    final literal = File(path.join(downloadPath, entry.dest));
    final present = File(path.join(downloadPath, decoded));
    if (literal.existsSync() || !present.existsSync()) continue;
    newEntries.add(MapEntry(entry.id, entry.copyWith(dest: decoded)));
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
      // nothing refers to it any more. A status that was never written is
      // settled the same way instead of staying empty forever.
      if (progress.status.isPending ||
          progress.status.isDownloading ||
          progress.status.isPaused ||
          progress.status.isEmpty) {
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

  // The cache copy and the batch path write an entry and its progress row in
  // two separate boxes, so a process death in between leaves a record the
  // list can show without a status, or with a status that was never written.
  // The missing row is rebuilt from the native task when one survives, and
  // from the file on disk otherwise. The updater APK is left to the updater,
  // which owns both of its records.
  final repaired = <String, DownloadProgress>{};
  for (final entry in entryBox.values) {
    if (entry.post.isReserved) continue;
    if (progressBox.containsKey(entry.id) || updates.containsKey(entry.id)) {
      continue;
    }

    final task = byId[entry.id];
    if (task != null) {
      final status = downloadStatusOf(task.status);
      final usable =
          !status.isDownloaded ||
          await _isCompletedFileUsable(downloadDir, entry);
      repaired[entry.id] = DownloadProgress(
        id: entry.id,
        status: usable ? status : DownloadStatus.failed,
        progress: task.progress,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      continue;
    }

    final usable = await _isCompletedFileUsable(downloadDir, entry);
    repaired[entry.id] = DownloadProgress(
      id: entry.id,
      status: usable ? DownloadStatus.downloaded : DownloadStatus.failed,
      progress: usable ? 100 : 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  if (updates.isNotEmpty) await progressBox.putAll(updates);
  if (repaired.isNotEmpty) await progressBox.putAll(repaired);
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

  final file = File(path.join(downloadDir, entry.dest));
  if (!isMediaFile(file)) return false;

  try {
    await StorageUtil().scanMedia(file.path);
  } catch (e) {
    mainLog.e('Downloads: failed to scan ${entry.dest}', e);
  }

  // A task that completed while the process was dead never reached the live
  // listener, so this is the only point that can write its metadata.
  await writeDownloadSidecar(root: downloadDir, entry: entry);
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

Future<Set<String>> _loadNativeTaskIds() async {
  try {
    final tasks = await FlutterDownloader.loadTasks();
    return tasks?.map((it) => it.taskId).toSet() ?? const {};
  } catch (e, stack) {
    mainLog.e('Downloads: failed to read the native tasks', e, stack);
    return const {};
  }
}

/// Normalizes a path read from a backup and refuses one that could leave the
/// download folder.
///
/// Only paths relative to that folder are ever written by this app, so an
/// absolute path or a parent hop belongs to a file the archive does not own.
/// A dot segment is refused as well: the metadata folder and the gallery
/// marker are not media the download list can point at.
///
/// The path is read literally. Every reader joins it to the download folder
/// without decoding, so a percent escape in an archive is part of a file name
/// and cannot be used to reach another directory.
String? _restoreDest(String dest) {
  if (dest.isEmpty || dest.contains('\x00')) return null;

  // Archives are written on Android, while a test or a desktop build may use
  // another separator. Reading the path as a portable one keeps both equal.
  final normalized = path.posix.normalize(dest.replaceAll('\\', '/'));
  if (path.posix.isAbsolute(normalized)) return null;

  final segments = normalized.split('/');
  if (segments.any((it) => it.isEmpty || it.startsWith('.'))) return null;
  return normalized;
}

/// Status a restored record may keep.
///
/// Only the terminal statuses survive: a pending, running, or paused record
/// would describe a native task this device does not have, and every action
/// for it would fail. Such a record becomes failed, which leaves the entry
/// retryable instead of dropping it.
DownloadStatus _restoredStatus(Object? raw) {
  return switch (raw) {
    'downloaded' => DownloadStatus.downloaded,
    'canceled' => DownloadStatus.canceled,
    _ => DownloadStatus.failed,
  };
}

int _restoredProgress(Object? raw, DownloadStatus status) {
  if (status.isDownloaded) return 100;
  if (raw is int) return raw.clamp(0, 100).toInt();
  return 0;
}

int _restoredTimestamp(Object? raw) {
  if (raw is int && raw > 0) return raw;
  return DateTime.now().millisecondsSinceEpoch;
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
