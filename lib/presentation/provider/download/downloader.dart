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
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    hide DownloadProgress;
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'downloader.g.dart';

@riverpod
Downloader downloader(Ref ref) {
  return Downloader(ref);
}

class Downloader {
  Downloader(this.ref);

  final Ref ref;

  /// Try to get file from cache, returns the cached file if available
  Future<File?> _getCachedFile(String url) async {
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        return fileInfo.file;
      }
    } catch (_) {}
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

      // Trigger media scan so it appears in gallery
      await MediaScanner.loadMedia(path: destPath);

      // Create a fake task ID for tracking
      final taskId = 'cache_${DateTime.now().millisecondsSinceEpoch}';

      final entry = DownloadEntry(
        id: taskId,
        post: post,
        dest: fileName,
      );
      await ref.read(downloadEntryStateProvider.notifier).add(entry);

      // Mark as completed immediately
      await ref.read(downloadProgressStateProvider.notifier).update(
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
    final fileName = Uri.decodeComponent(fileUrl.fileName)
        .replaceAll(RegExp(r'([^a-zA-Z0-9\s\.\(\)_]+)'), '_');

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
    return _downloadFromNetwork(post, fileUrl, fileName, dest);
  }

  Future<String?> _downloadFromNetwork(
    Post post,
    String fileUrl,
    String fileName,
    String Function(String fileName)? dest,
  ) async {
    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);
    await sharedStorageHandle.init();

    final versionRepo = ref.read(versionRepoProvider);
    final taskId = await FlutterDownloader.enqueue(
      url: fileUrl,
      fileName: fileName,
      savedDir: sharedStorageHandle.path,
      showNotification: true,
      openFileFromNotification: true,
      headers: HeadersFactory.builder()
          .setUserAgent(versionRepo.current)
          .setReferer(createReferer(fileUrl))
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
    if (newId != null) {
      final newEntry = ref
          .read(downloadEntryStateProvider)
          .firstWhere((it) => it.id == id, orElse: DownloadEntry.new)
          .copyWith(id: newId);

      await ref.read(downloadEntryStateProvider.notifier).update(id, newEntry);
    }
  }

  Future<void> cancel({required String id}) async {
    await FlutterDownloader.cancel(taskId: id);
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
