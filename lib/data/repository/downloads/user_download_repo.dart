import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/domain/repository/downloads_repo.dart';
import 'package:boorusphere/pigeon/storage_util.pi.dart';
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
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks != null) {
      await Future.wait(
        tasks.map(
          (e) async => await FlutterDownloader.remove(
            taskId: e.taskId,
            shouldDeleteContent: false,
          ),
        ),
      );
    }

    await entryBox.deleteAll(entryBox.keys);
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
    await _adaptEntryDest(entryBox);
    await _migrateProgresses(progressBox);
    await FlutterDownloader.initialize();
    await _syncProgresses(entryBox, progressBox);
  }
}

Future<void> _adaptEntryDest(Box<DownloadEntry> box) async {
  if (box.isEmpty) {
    return;
  }
  var downloadPath = await StorageUtil().getDownloadPath();
  downloadPath = path.join(downloadPath, 'Boorusphere');
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

  for (final progress in progressBox.values) {
    final task = byId.remove(progress.id);
    if (task == null) {
      // No native task behind the row: drop it once its entry is gone too,
      // otherwise a row left in flight by a dead process would never settle.
      if (!entryBox.containsKey(progress.id)) {
        orphans.add(progress.id);
      } else if (progress.status.isPending || progress.status.isDownloading) {
        updates[progress.id] = progress.copyWith(
          status: DownloadStatus.failed,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
      }
      continue;
    }

    final status = _statusOf(task.status);
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

DownloadStatus _statusOf(DownloadTaskStatus status) {
  return switch (status) {
    DownloadTaskStatus.undefined => DownloadStatus.empty,
    DownloadTaskStatus.enqueued => DownloadStatus.pending,
    DownloadTaskStatus.running => DownloadStatus.downloading,
    DownloadTaskStatus.complete => DownloadStatus.downloaded,
    DownloadTaskStatus.failed => DownloadStatus.failed,
    DownloadTaskStatus.canceled => DownloadStatus.canceled,
    DownloadTaskStatus.paused => DownloadStatus.paused,
  };
}

Future<void> _migrateProgresses(Box<DownloadProgress> box) async {
  const dbName = 'download_tasks.db';
  if (!(await sqflite.databaseExists(dbName))) {
    return;
  }

  final db = await sqflite.openReadOnlyDatabase(dbName);
  try {
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
    await db.close();
  }
}
