import 'dart:io';

import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    hide DownloadProgress;
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:media_scanner/media_scanner.dart';
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

  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;

  static Future<void> _ensureNotificationsInitialized() async {
    if (_notificationsInitialized) return;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    await _notifications.initialize(
      const InitializationSettings(android: androidSettings),
    );
    _notificationsInitialized = true;
  }

  Future<void> _showDownloadCompleteNotification(String fileName) async {
    await _ensureNotificationsInitialized();
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Download complete',
      fileName,
      const NotificationDetails(
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
    await sharedStorageHandle.init();

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
      await MediaScanner.loadMedia(path: destPath);

      // Show notification for cached download
      await _showDownloadCompleteNotification(fileName);

      // Create a fake task ID for tracking
      final taskId = 'cache_${DateTime.now().millisecondsSinceEpoch}';

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
    final fileUrl = url ?? post.originalFile;
    // sanitize forbidden characters on the file name
    final fileName = decodeComponentSafely(
      fileUrl.fileName,
    ).replaceAll(RegExp(r'([^a-zA-Z0-9\s\.\(\)_]+)'), '_');

    try {
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

  Future<String?> _downloadFromNetwork(
    Post post,
    String fileUrl,
    String fileName,
    String Function(String fileName)? dest,
  ) async {
    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);
    await sharedStorageHandle.init();
    // init() swallows the failure that leaves the folder missing, and enqueuing
    // into it would only produce a task that cannot write its file.
    if (!Directory(sharedStorageHandle.path).existsSync()) {
      mainLog.e('Downloader: download folder is not writable');
      return null;
    }

    final versionRepo = ref.read(versionRepoProvider);
    // Use post URL for referer (like image viewer does), not file URL
    final refererUrl = post.postUrl.isEmpty ? fileUrl : post.postUrl;
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
    }
    return taskId;
  }

  Future<void> retry({required String id}) async {
    final newId = await FlutterDownloader.retry(taskId: id);
    if (newId == null) return;

    final entry = ref.read(downloadEntryStateProvider).getById(id);
    if (entry.id.isEmpty) return;

    // The retried task carries a new id from here on, so nothing would ever
    // write the row of the old one again.
    await ref.read(downloadProgressStateProvider.notifier).remove(id);
    await ref
        .read(downloadEntryStateProvider.notifier)
        .update(id, entry.copyWith(id: newId));
  }

  Future<void> cancel({required String id}) async {
    await FlutterDownloader.cancel(taskId: id);
    // The native side only flags the task; without a callback the row keeps
    // reporting the download as running.
    final progress = ref.read(downloadProgressStateProvider).getById(id);
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

  Future<void> clear({required String id}) async {
    await FlutterDownloader.remove(taskId: id, shouldDeleteContent: false);
    await ref.read(downloadEntryStateProvider.notifier).remove(id);
  }

  void openFile({required String id}) {
    final entry = ref.read(downloadEntryStateProvider).getById(id);
    ref.read(sharedStorageHandleProvider).open(entry.dest);
  }
}
