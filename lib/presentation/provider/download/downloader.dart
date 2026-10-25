import 'dart:io';

import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/provider.dart';
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

    try {
      // Resolved once so the cache copy and the queued task write the same
      // path, and so the entry reports the name the file actually got.
      final fileName = await _uniqueFileName(fileUrl);

      // Try to use cached file first if enabled
      if (preferCache) {
        final cachedFile = await _getCachedFile(fileUrl);
        if (cachedFile != null) {
          final taskId = await _copyFromCache(cachedFile, post, fileName);
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
    }
  }

  /// File name for [fileUrl] that neither a queued entry nor an existing file
  /// in the download folder already claims.
  ///
  /// The native worker opens the target path in append mode, so a second
  /// download resolving to a name already on disk would resume the first one's
  /// bytes and both would end up reporting a corrupt file as complete. A
  /// leading dot is stripped as well: a name like '.nomedia' would hide the
  /// whole folder from the gallery.
  Future<String> _uniqueFileName(String fileUrl) async {
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
        sharedStorageHandle.fileExists(candidate)) {
      candidate = '${base}_${suffix++}$ext';
    }
    return candidate;
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
    // The native worker re-sends these headers on every redirect hop
    // (DownloadWorker.kt), so only the cookies of the file's own host apply.
    final cookies = await ref
        .read(cookieJarProvider)
        .loadForRequest(fileUrl.toUri());
    final taskId = await FlutterDownloader.enqueue(
      url: fileUrl,
      fileName: fileName,
      savedDir: sharedStorageHandle.path,
      showNotification: true,
      openFileFromNotification: true,
      headers: HeadersFactory.builder()
          .setUserAgent(versionRepo.current)
          .setReferer(createReferer(refererUrl))
          .setCookies(cookies)
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
      // which never happens while the device is offline.
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
    return taskId;
  }

  Future<void> retry({required String id}) async {
    final newId = await FlutterDownloader.retry(taskId: id);
    if (newId == null) return;

    final entry = ref.read(downloadEntryStateProvider).getById(id);
    if (entry.id.isEmpty) return;

    // The retried task carries a new id from here on, so nothing would ever
    // write the row of the old one again. The record moves to the new id
    // first: a death before the old rows are dropped leaves a duplicate the
    // boot reconciliation settles, while dropping them first would leave the
    // running task with nothing pointing at it.
    await ref
        .read(downloadEntryStateProvider.notifier)
        .update(id, entry.copyWith(id: newId));
    await ref.read(downloadProgressStateProvider.notifier).remove(id);
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

    await FlutterDownloader.cancel(taskId: id);
    if (!id.startsWith(_cacheTaskPrefix)) {
      // cancel() only stops the work; its database row survives and boot-time
      // reconciliation would read it back as pending forever.
      await FlutterDownloader.remove(taskId: id, shouldDeleteContent: false);
    }

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
    } catch (e) {
      mainLog.e('Downloader: failed to delete $dest', e);
    }
  }

  void openFile({required String id}) {
    final entry = ref.read(downloadEntryStateProvider).getById(id);
    ref.read(sharedStorageHandleProvider).open(entry.dest);
  }
}
