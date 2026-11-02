import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';

abstract interface class DownloadsRepo {
  Iterable<DownloadEntry> getEntries();
  Iterable<DownloadProgress> getProgresses();
  Future<void> addEntry(DownloadEntry entry);
  Future<void> updateProgress(DownloadProgress progress);
  Future<void> removeEntry(String id);
  Future<void> removeProgress(String id);

  /// Drops every download record and reports the ids that were kept.
  ///
  /// A record owned by another part of the app (the updater APK) survives a
  /// clear, so its progress row has to survive as well.
  Future<Set<String>> clearEntries();
  Future<void> clearProgresses();
  Future<void> import(String src);
  Future<BackupItem> export();
}
