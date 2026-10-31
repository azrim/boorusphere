import 'dart:io';

import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/pigeon/storage_util.pi.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    hide DownloadProgress;
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'downloader.g.dart';

/// Kept alive for the session: the object is a stateless facade over [Ref] and
/// every caller only reads it, so an auto-disposed element would be gone by the
/// first await inside a download and the next ref.read would throw.
@Riverpod(keepAlive: true)
Downloader downloader(Ref ref) {
  return Downloader(ref);
}

class Downloader {
  Downloader(this.ref);

  final Ref ref;

  /// Prefix of the task ids minted for downloads served from the image cache.
  /// They have no native task behind them, so every platform call that takes a
  /// task id has to be skipped for them.
  static const _cacheTaskPrefix = 'cache_';

  /// Names a download has claimed but not published as an entry yet, so two
  /// downloads started in the same frame cannot settle on one name.
  final _reservedNames = <String>{};

  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;

  static Future<void> _ensureNotificationsInitialized() async {
    if (_notificationsInitialized) return;
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    await _notifications.initialize(
      settings: const InitializationSettings(android: androidSettings),
    );
    _notificationsInitialized = true;
  }

  Future<void> _showDownloadCompleteNotification(String fileName) async {
    await _ensureNotificationsInitialized();
    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Download complete',
      body: fileName,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'download_complete',
          'Download Complete',
          channelDescription: 'Notifications for completed downloads',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
        ),
      ),
    );
  }

  /// Try to get file from the cached_network_image disk cache
  Future<File?> _getCachedFile(String url) async {
    try {
      final info = await DefaultCacheManager().getFileFromCache(url);
      final file = info?.file;
      if (file != null && file.existsSync()) {
        return file;
      }
    } catch (e) {
      mainLog.e('Downloader: Failed to get cached file', e);
    }
    return null;
  }

  /// Copy cached file to downloads folder
  Future<String?> _copyFromCache(
    File cachedFile,
    Post post,
    String fileName,
    String url,
  ) async {
    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);
    if (!await sharedStorageHandle.init()) return null;

    final destPath = p.join(sharedStorageHandle.path, fileName);

    try {
      // Copy the cached file to downloads
      await cachedFile.copy(destPath);

      // Verify the file was copied
      final destFile = File(destPath);
      if (!destFile.existsSync()) {
        return null;
      }

      // The disk cache keeps the body even when it cannot be decoded as an
      // image (the provider only evicts its memory entry), so the bytes are
      // checked before the row may claim success. The bad copy and its cache
      // entry are dropped so the network below is tried instead of copying
      // the same page again.
      if (!sharedStorageHandle.isValidMedia(destPath)) {
        mainLog.w('Downloader: cached file for $url is not media');
        await _deleteFile(destFile);
        await _evictCache(url);
        return null;
      }

      // Trigger media scan so it appears in gallery
      await StorageUtil().scanMedia(destPath);

      // Show notification for cached download
      await _showDownloadCompleteNotification(fileName);

      // Create a fake task ID for tracking
      final taskId =
          '$_cacheTaskPrefix${DateTime.now().millisecondsSinceEpoch}';

      final entry = DownloadEntry(id: taskId, post: post, dest: fileName);
      await ref.read(downloadEntryStateProvider.notifier).add(entry);

      // Mark as completed immediately
      await ref
          .read(downloadProgressStateProvider.notifier)
          .update(
            DownloadProgress(
              id: taskId,
              progress: 100,
              status: DownloadStatus.downloaded,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      return taskId;
    } catch (e) {
      // If copy fails, fall back to network download
      return null;
    }
  }

  Future<void> _deleteFile(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (e) {
      mainLog.e('Downloader: failed to delete ${file.path}', e);
    }
  }

  Future<void> _evictCache(String url) async {
    try {
      await DefaultCacheManager().removeFile(url);
    } catch (e) {
      mainLog.e('Downloader: failed to evict the cached $url', e);
    }
  }

  Future<String?> download(
    Post post, {
    String? url,
    String Function(String fileName)? dest,
    bool preferCache = true,
  }) async {
    // Some engines answer with an empty sample url for small images, and an
    // empty url only ever produces a task that fails right away.
    final fileUrl = url != null && url.isNotEmpty ? url : post.originalFile;
    if (fileUrl.isEmpty) return null;

    String? fileName;
    try {
      // Resolved once so the cache copy and the queued task write the same
      // path, and so the entry reports the name the file actually got.
      fileName = claimFileName(fileUrl);

      // Try to use cached file first if enabled
      if (preferCache) {
        final cachedFile = await _getCachedFile(fileUrl);
        if (cachedFile != null) {
          final taskId = await _copyFromCache(
            cachedFile,
            post,
            fileName,
            fileUrl,
          );
          if (taskId != null) {
            return taskId;
          }
        }
      }

      // Fall back to network download
      return await _downloadFromNetwork(post, fileUrl, fileName, dest);
    } catch (e, stack) {
      // The caller drives the UI from the result: an exception here would
      // escape its pending flag and leave the control disabled for good.
      mainLog.e('Downloader: failed to start $fileUrl', e, stack);
      return null;
    } finally {
      // The claim covers only the gap before the entry is published, and the
      // entry list is what keeps the name taken from then on.
      if (fileName != null) releaseName(fileName);
    }
  }

  /// File name for [fileUrl] that neither a queued entry, a download started
  /// moments ago nor an existing file in the download folder already claims.
  ///
  /// The native worker opens the target path in append mode, so a second
  /// download resolving to a name already on disk would resume the first one's
  /// bytes and both would end up reporting a corrupt file as complete. A
  /// leading dot is stripped as well: a name like '.nomedia' would hide the
  /// whole folder from the gallery.
  ///
  /// The name is claimed here and stays claimed until [releaseName]: the batch
  /// path names its files through this as well, so two downloads started from
  /// different screens cannot settle on the same path.
  String claimFileName(String fileUrl) {
    final decoded = decodeComponentSafely(fileUrl.fileName);
    final sanitized = decoded
        .replaceAll(RegExp(r'([^a-zA-Z0-9\s\.\(\)_\-]+)'), '_')
        .replaceFirst(RegExp(r'^\.+'), '');
    final dot = sanitized.lastIndexOf('.');
    final stem = (dot > 0 ? sanitized.substring(0, dot) : sanitized).trim();
    final ext = dot > 0 ? sanitized.substring(dot) : '';
    final base = stem.isEmpty ? 'image' : stem;

    final taken = ref
        .read(downloadEntryStateProvider)
        .map((it) => p.basename(it.dest))
        .toSet();
    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);

    var candidate = '$base$ext';
    var suffix = 1;
    while (taken.contains(candidate) ||
        _reservedNames.contains(candidate) ||
        sharedStorageHandle.fileExists(candidate)) {
      candidate = '${base}_${suffix++}$ext';
    }
    _reservedNames.add(candidate);
    return candidate;
  }

  /// Gives a name claimed by [claimFileName] back once its entry exists or the
  /// download never started.
  void releaseName(String fileName) {
    _reservedNames.remove(fileName);
  }

  Future<String?> _downloadFromNetwork(
    Post post,
    String fileUrl,
    String fileName,
    String Function(String fileName)? dest,
  ) async {
    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);
    // Enqueuing into a folder that does not exist only produces a task that
    // cannot write its file.
    if (!await sharedStorageHandle.init()) {
      mainLog.e('Downloader: download folder is not writable');
      return null;
    }

    final versionRepo = ref.read(versionRepoProvider);
    // Use post URL for referer (like image viewer does), not file URL
    final refererUrl = post.postUrl.isEmpty ? fileUrl : post.postUrl;
    // No Cookie header: the native worker re-sends every header it is given on
    // each redirect hop (DownloadWorker.kt), so a session cookie for the booru
    // would follow the request to whatever CDN it redirects to. Media is
    // fetched anonymously; the Referer and User-Agent are what hotlink
    // protection checks.
    final taskId = await FlutterDownloader.enqueue(
      url: fileUrl,
      fileName: fileName,
      savedDir: sharedStorageHandle.path,
      showNotification: true,
      openFileFromNotification: true,
      headers: HeadersFactory.builder()
          .setUserAgent(versionRepo.current)
          .setReferer(createReferer(refererUrl))
          .build(),
    );

    if (taskId != null) {
      final entry = DownloadEntry(
        id: taskId,
        post: post,
        dest: dest?.call(fileName) ?? fileName,
      );
      await ref.read(downloadEntryStateProvider.notifier).add(entry);
      // The plugin's ENQUEUED event has no Dart handler, so without this row
      // the entry keeps reporting an empty status until the worker starts,
      // which never happens while the device is offline. A task that already
      // reported itself keeps the status it wrote.
      final current = ref.read(downloadProgressStateProvider).getById(taskId);
      if (current.status.isEmpty) {
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
      }
    }
    return taskId;
  }

  Future<void> retry({required String id}) async {
    final entry = ref.read(downloadEntryStateProvider).getById(id);
    if (entry.id.isEmpty) return;

    final newId = await FlutterDownloader.retry(taskId: id);
    if (newId != null) {
      // The retried task carries a new id from here on, so nothing would ever
      // write the row of the old one again. The record moves to the new id
      // first: a death before the old rows are dropped leaves a duplicate the
      // boot reconciliation settles, while dropping them first would leave the
      // running task with nothing pointing at it.
      await ref
          .read(downloadEntryStateProvider.notifier)
          .update(id, entry.copyWith(id: newId));
      await ref.read(downloadProgressStateProvider.notifier).remove(id);

      // The plugin reports ENQUEUED to nobody, so the moved record would keep
      // its failed or canceled status until the worker happens to run.
      final current = ref.read(downloadProgressStateProvider).getById(newId);
      if (current.status.isEmpty) {
        await ref
            .read(downloadProgressStateProvider.notifier)
            .update(
              DownloadProgress(
                id: newId,
                status: DownloadStatus.pending,
                progress: 0,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );
      }
      return;
    }

    // The plugin only retries a FAILED or CANCELED row. A download cancelled
    // before its worker started keeps an ENQUEUED row that no Worker will ever
    // report, so the platform refuses it and the row here can never recover on
    // its own. The task is started again from the URL recorded with it.
    await _reenqueue(entry);
  }

  /// Starts the download behind [entry] again from scratch.
  ///
  /// The URL only survives in the native task row, so that row is read before
  /// it is dropped; the refused row would otherwise be read back as live by
  /// the boot reconciliation.
  Future<void> _reenqueue(DownloadEntry entry) async {
    if (entry.post.isReserved) return;

    final task = await _taskById(entry.id);
    if (task == null || task.url.isEmpty) {
      mainLog.w('Downloader: no URL left to restart ${entry.id}');
      return;
    }

    await FlutterDownloader.remove(
      taskId: entry.id,
      shouldDeleteContent: false,
    );
    // Whatever the failed attempt left is either partial or not media at all.
    await _deleteLocalContent(entry.dest);

    final newId = await download(entry.post, url: task.url, preferCache: false);
    if (newId == null) {
      mainLog.w('Downloader: failed to restart ${entry.id}');
      return;
    }

    // The replacement record is in place; the old one goes last so a failed
    // start above left the user something to retry from.
    await ref.read(downloadEntryStateProvider.notifier).remove(entry.id);
  }

  Future<DownloadTask?> _taskById(String id) async {
    try {
      final tasks = await FlutterDownloader.loadTasks();
      if (tasks == null) return null;
      for (final task in tasks) {
        if (task.taskId == id) return task;
      }
    } catch (e, stack) {
      mainLog.e('Downloader: failed to read the task $id', e, stack);
    }
    return null;
  }

  Future<void> cancel({required String id}) async {
    // Cancelling a finished task would downgrade its row: the native side
    // rejects retrying a completed task, so the entry could never recover.
    if (ref
        .read(downloadProgressStateProvider)
        .getById(id)
        .status
        .isDownloaded) {
      return;
    }

    // The task row is left in place: retry() re-enqueues from it, and boot
    // reconciliation reads a canceled row back as canceled.
    await FlutterDownloader.cancel(taskId: id);

    // The task may have completed while the channel call was in flight.
    final progress = ref.read(downloadProgressStateProvider).getById(id);
    if (progress.status.isDownloaded) return;

    await ref
        .read(downloadProgressStateProvider.notifier)
        .update(
          DownloadProgress(
            id: id,
            status: DownloadStatus.canceled,
            progress: progress.progress,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// Drops the record of [id] and leaves the file on disk.
  ///
  /// The record and the bytes are separate: the list is a log of what was
  /// downloaded, and forgetting an entry does not mean the file has to go.
  /// [deleteContent] is the action that removes the file.
  Future<void> clear({required String id}) async {
    if (!id.startsWith(_cacheTaskPrefix)) {
      // Also drops the native task row, which would otherwise be read back as
      // a pending download at the next boot.
      await FlutterDownloader.remove(taskId: id, shouldDeleteContent: false);
    }
    await ref.read(downloadEntryStateProvider.notifier).remove(id);
  }

  /// Deletes the file behind [entry], keeping its record so the row can still
  /// offer a redownload.
  Future<void> deleteContent(DownloadEntry entry) async {
    if (entry.id.startsWith(_cacheTaskPrefix)) {
      await _deleteLocalContent(entry.dest);
      return;
    }

    try {
      await FlutterDownloader.remove(
        taskId: entry.id,
        shouldDeleteContent: true,
      );
    } catch (e, stack) {
      mainLog.e('Downloader: failed to remove task', e, stack);
    }

    // The plugin only deletes the file of a task it still tracks, and the boot
    // reconciliation prunes tasks whose file never landed: a leftover file is
    // removed by its path instead.
    await _deleteLocalContent(entry.dest);
  }

  Future<void> _deleteLocalContent(String dest) async {
    if (dest.isEmpty) return;

    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);
    if (!sharedStorageHandle.fileExists(dest)) return;

    try {
      final file = File(p.join(sharedStorageHandle.path, Uri.decodeFull(dest)));
      await file.delete();
      // The bytes are gone but the gallery keeps its row for the path, which
      // turns into a thumbnail that cannot be opened: scanning the removed
      // path is what drops it.
      await sharedStorageHandle.rescanFile(dest);
      ref.read(downloadFileRevisionProvider.notifier).bump();
    } catch (e) {
      mainLog.e('Downloader: failed to delete $dest', e);
    }
  }

  void openFile({required String id}) {
    final entry = ref.read(downloadEntryStateProvider).getById(id);
    ref.read(sharedStorageHandleProvider).open(entry.dest);
  }
}
