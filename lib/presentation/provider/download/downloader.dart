import 'dart:io';

import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/download_folder.dart';
import 'package:boorusphere/data/repository/downloads/download_sidecar.dart';
import 'package:boorusphere/data/repository/downloads/download_status_mapper.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/pigeon/storage_util.pi.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/download_setting_state.dart';
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

  /// Prefix of the task ids minted by the batch path, which writes its files
  /// itself and never enqueues anything the plugin could pause or resume.
  static const _batchTaskPrefix = 'batch_';

  /// Whether [id] belongs to a task the download plugin knows about.
  static bool _hasNativeTask(String id) =>
      !id.startsWith(_cacheTaskPrefix) && !id.startsWith(_batchTaskPrefix);

  /// Names a download has claimed but not published as an entry yet, so two
  /// downloads started in the same frame cannot settle on one name.
  final _reservedNames = <String>{};

  /// Ids whose resume call is still in the channel, so a second tap cannot
  /// start a second native task for the same paused download.
  final _resuming = <String>{};

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
    String folder,
  ) async {
    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);
    if (!await sharedStorageHandle.init()) return null;

    if (folder.isNotEmpty) sharedStorageHandle.createSubDir(folder);
    final destPath = p.join(sharedStorageHandle.path, folder, fileName);
    final destFile = File(destPath);
    DownloadEntry? entry;

    try {
      // Copy the cached file to downloads
      await cachedFile.copy(destPath);

      // Verify the file was copied
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

      // Trigger media scan so it appears in gallery. A scan that fails says
      // nothing about the bytes, so the record is still written: the next boot
      // scans the finished file again.
      try {
        await StorageUtil().scanMedia(destPath);
      } catch (e) {
        mainLog.e('Downloader: failed to scan $destPath', e);
      }

      // Show notification for cached download. The notification reports a
      // finished record, it is not a condition for having one.
      try {
        await _showDownloadCompleteNotification(fileName);
      } catch (e) {
        mainLog.e('Downloader: failed to notify $fileName', e);
      }

      // Create a fake task ID for tracking
      final taskId =
          '$_cacheTaskPrefix${DateTime.now().millisecondsSinceEpoch}';

      entry = DownloadEntry(
        id: taskId,
        post: post,
        dest: p.join(folder, fileName),
      );
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

      // The cached path already holds the finished bytes, so its metadata is
      // written here instead of waiting for a plugin event that never comes.
      await writeDownloadSidecar(root: sharedStorageHandle.path, entry: entry);

      return taskId;
    } catch (e, stack) {
      // A copy or a record write can fail halfway. The file and any record
      // already published are dropped before the network path runs: keeping
      // either would leave a row whose file is unreadable, while a failed copy
      // would be resumed by a later attempt on the same name.
      mainLog.e('Downloader: failed to copy $url from the cache', e, stack);
      await _deleteFile(destFile);
      final failedEntry = entry;
      if (failedEntry != null) {
        await deleteDownloadSidecar(
          root: sharedStorageHandle.path,
          dest: failedEntry.dest,
        );
        try {
          await ref
              .read(downloadEntryStateProvider.notifier)
              .remove(failedEntry.id);
        } catch (e, stack) {
          mainLog.e('Downloader: failed to drop ${failedEntry.id}', e, stack);
        }
      }
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
      final folder = _folderFor(post);
      fileName = claimFileName(fileUrl, folder: folder);

      // Try to use cached file first if enabled
      if (preferCache) {
        final cachedFile = await _getCachedFile(fileUrl);
        if (cachedFile != null) {
          final taskId = await _copyFromCache(
            cachedFile,
            post,
            fileName,
            fileUrl,
            folder,
          );
          if (taskId != null) {
            return taskId;
          }
        }
      }

      // Fall back to network download
      return await _downloadFromNetwork(post, fileUrl, fileName, folder, dest);
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
  /// moments ago nor an existing file in [folder] already claims.
  ///
  /// The native worker opens the target path in append mode, so a second
  /// download resolving to a name already on disk would resume the first one's
  /// bytes and both would end up reporting a corrupt file as complete. A
  /// leading dot is stripped as well: a name like '.nomedia' would hide the
  /// whole folder from the gallery.
  ///
  /// Entries keep names unique across folders: two servers can hold a file
  /// with the same name, but a row that only shows the base name would make
  /// the pair indistinguishable. Only the disk check looks inside [folder],
  /// since the same name in another folder is not in the way.
  ///
  /// The name is claimed here and stays claimed until [releaseName]: the batch
  /// path names its files through this as well, so two downloads started from
  /// different screens cannot settle on the same path.
  String claimFileName(String fileUrl, {String folder = ''}) {
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
        sharedStorageHandle.fileExists(p.join(folder, candidate))) {
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

  /// Folder a new file of [post] is written into.
  ///
  /// Resolved once per download: the setting may change while a transfer runs,
  /// and a queued task keeps writing to the folder it was enqueued into.
  String _folderFor(Post post) {
    return downloadFolderOf(
      post,
      servers: ref.read(serverStateProvider),
      groupByServer: ref.read(downloadSettingStateProvider).groupByServer,
    );
  }

  Future<String?> _downloadFromNetwork(
    Post post,
    String fileUrl,
    String fileName,
    String folder,
    String Function(String fileName)? dest,
  ) async {
    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);
    // Enqueuing into a folder that does not exist only produces a task that
    // cannot write its file.
    if (!await sharedStorageHandle.init()) {
      mainLog.e('Downloader: download folder is not writable');
      return null;
    }
    final savedDir = folder.isEmpty
        ? sharedStorageHandle.path
        : sharedStorageHandle.createSubDir(folder).path;

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
      savedDir: savedDir,
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
        dest: dest?.call(fileName) ?? p.join(folder, fileName),
      );
      try {
        await ref.read(downloadEntryStateProvider.notifier).add(entry);
      } catch (e, stack) {
        // The worker is already running, but no record refers to it: its
        // completion event would be dropped and its file would land where no
        // row points. The task and whatever it already wrote are removed.
        mainLog.e('Downloader: failed to record the task $taskId', e, stack);
        try {
          await FlutterDownloader.remove(
            taskId: taskId,
            shouldDeleteContent: true,
          );
        } catch (e, stack) {
          mainLog.e('Downloader: failed to drop the task $taskId', e, stack);
        }
        return null;
      }

      // The plugin's ENQUEUED event has no Dart handler, so without this row
      // the entry keeps reporting an empty status until the worker starts,
      // which never happens while the device is offline. A task that already
      // reported itself keeps the status it wrote. A write that fails here is
      // rebuilt from the native row at the next boot, so it cannot take the
      // running download down with it.
      try {
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
      } catch (e, stack) {
        mainLog.e(
          'Downloader: failed to record the pending state of $taskId',
          e,
          stack,
        );
      }
    }
    return taskId;
  }

  /// Retries the download behind [id] and reports whether it restarted.
  ///
  /// The platform retry keeps the task id; the fallback starts a new task and
  /// moves the record, so the caller's id no longer names the download after
  /// a successful fallback.
  Future<bool> retry({required String id}) async {
    final entry = ref.read(downloadEntryStateProvider).getById(id);
    if (entry.id.isEmpty) return false;

    final task = _hasNativeTask(id) ? await _taskById(id) : null;
    String? newId;
    if (task != null) {
      try {
        newId = await FlutterDownloader.retry(taskId: id);
      } catch (e, stack) {
        mainLog.w('Downloader: the platform cannot retry $id', e, stack);
      }
    }
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
      return true;
    }

    // The plugin only retries a FAILED or CANCELED row. A download cancelled
    // before its worker started keeps an ENQUEUED row that no Worker will ever
    // report, so the platform refuses it and the row here can never recover on
    // its own. The task is started again from the URL recorded with it, or from
    // the post when no native row survives.
    return _reenqueue(entry, task: task);
  }

  /// Length the server reports for the file behind [id], or null when it
  /// cannot be read.
  ///
  /// The native worker treats the end of the response stream as a finished
  /// transfer, so a connection the server drops mid-body still arrives as
  /// COMPLETE with a short file. Only the length from the server separates
  /// that from a whole download; a host that rejects the request or sends no
  /// length yields null, leaving the caller with the header check alone.
  Future<int?> expectedSizeOf(String id) async {
    if (!_hasNativeTask(id)) return null;
    final task = await _taskById(id);
    if (task == null || task.url.isEmpty) return null;
    final uri = Uri.tryParse(task.url);
    if (uri == null) return null;

    final entry = ref.read(downloadEntryStateProvider).getById(id);
    final pageUrl = entry.post.postUrl.isEmpty ? task.url : entry.post.postUrl;
    final headers = HeadersFactory.builder()
        .setUserAgent(ref.read(versionRepoProvider).current)
        .setReferer(createReferer(pageUrl))
        .build();

    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = _sizeProbeTimeout;
    try {
      try {
        final head = await _probeSize(client, uri, headers, head: true);
        if (head != null) return head;
      } catch (e) {
        // A host that closes the connection on HEAD still answers the range
        // request below.
        mainLog.w('Downloader: HEAD probe failed for ${task.url}', e);
      }

      // A host that denies HEAD or leaves the length out of the answer still
      // reports the whole size of a one-byte range request in `Content-Range`.
      return await _probeSize(client, uri, headers, head: false);
    } catch (e) {
      mainLog.w('Downloader: no length for ${task.url}', e);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Length the server reports for [uri], or null when the answer carries
  /// none.
  ///
  /// The body is never read: the response is dropped together with the client
  /// in [expectedSizeOf], so a host that ignores the range cannot stream a
  /// whole file just for the probe.
  Future<int?> _probeSize(
    HttpClient client,
    Uri uri,
    Map<String, String> headers, {
    required bool head,
  }) async {
    final request = head ? await client.headUrl(uri) : await client.getUrl(uri);
    request.followRedirects = true;
    // The worker fetches media anonymously; the probe keeps the same request
    // and only adds the headers hotlink protection checks.
    headers.forEach((name, value) => request.headers.set(name, value));
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (!head) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    }

    final response = await request.close().timeout(_sizeProbeTimeout);
    if (response.statusCode == HttpStatus.ok) {
      final length = response.contentLength;
      return length > 0 ? length : null;
    }
    if (!head && response.statusCode == HttpStatus.partialContent) {
      final range = response.headers.value(HttpHeaders.contentRangeHeader);
      if (range == null) return null;
      final slash = range.lastIndexOf('/');
      if (slash < 0) return null;
      final total = int.tryParse(range.substring(slash + 1).trim());
      return total != null && total > 0 ? total : null;
    }
    return null;
  }

  static const _sizeProbeTimeout = Duration(seconds: 5);

  /// Retries every failed entry that is not a reserved updater task.
  ///
  /// One at a time: a burst of retries would open as many requests at once
  /// and let several name claims race for the same path. A row that cannot be
  /// retried is skipped without stopping the rest, and the count returned is
  /// the number of entries that really restarted.
  Future<int> retryAllFailed() async {
    final entries = ref
        .read(downloadEntryStateProvider)
        .whereNotReserved()
        .where(
          (it) => ref
              .read(downloadProgressStateProvider)
              .getById(it.id)
              .status
              .isFailed,
        )
        .toList();

    var retried = 0;
    for (final entry in entries) {
      try {
        if (await retry(id: entry.id)) retried++;
      } catch (e, stack) {
        mainLog.e('Downloader: failed to retry ${entry.id}', e, stack);
      }
    }
    return retried;
  }

  /// Pauses the native task behind [id], keeping its partial file.
  ///
  /// Cache and batch rows have no native task. The pause call reports nothing,
  /// so the task is read back afterwards: a worker that finished or failed in
  /// the meantime reports that state instead of being relabelled paused.
  Future<void> pause({required String id}) async {
    if (!_hasNativeTask(id)) return;

    final progress = ref.read(downloadProgressStateProvider).getById(id);
    // Only a running download can be paused; a finished row would only be
    // downgraded, and an enqueued task that no worker has picked up cannot
    // report the paused state the row would need to offer a resume.
    if (!progress.status.isDownloading) return;

    try {
      await FlutterDownloader.pause(taskId: id);
    } catch (e, stack) {
      mainLog.e('Downloader: failed to pause $id', e, stack);
    }

    final latest = ref.read(downloadProgressStateProvider).getById(id);
    if (latest.status.isDownloaded) return;

    final task = await _taskById(id);
    if (task != null && task.status != DownloadTaskStatus.undefined) {
      await ref
          .read(downloadProgressStateProvider.notifier)
          .update(
            DownloadProgress(
              id: id,
              status: downloadStatusOf(task.status),
              progress: task.progress.clamp(0, 100).toInt(),
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      return;
    }

    // The row is gone from the queue but the download did not report a
    // terminal state: keep the last progress and let the boot reconciliation
    // settle a task that really disappeared.
    await ref
        .read(downloadProgressStateProvider.notifier)
        .update(
          DownloadProgress(
            id: id,
            status: DownloadStatus.paused,
            progress: latest.progress,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// Resumes the native task behind [id].
  ///
  /// The plugin restarts a paused task under a new id, so the entry and its
  /// progress move to that id exactly like [retry]: the replacement record is
  /// written before the old one goes, and a death in between leaves a
  /// duplicate the boot reconciliation settles.
  Future<void> resume({required String id}) async {
    if (!_hasNativeTask(id)) return;
    if (!_resuming.add(id)) return;

    try {
      final progress = ref.read(downloadProgressStateProvider).getById(id);
      if (!progress.status.isPaused) return;

      final entry = ref.read(downloadEntryStateProvider).getById(id);
      if (entry.id.isEmpty) return;

      String? newId;
      try {
        newId = await FlutterDownloader.resume(taskId: id);
      } catch (e, stack) {
        mainLog.e('Downloader: failed to resume $id', e, stack);
      }

      if (newId == null) {
        // The plugin only resumes a row it still tracks as paused. A row the
        // platform no longer knows about has to start from its recorded URL,
        // the same fallback retry uses for a stale enqueued task.
        await _reenqueue(entry);
        return;
      }

      if (newId != id) {
        await ref
            .read(downloadEntryStateProvider.notifier)
            .update(id, entry.copyWith(id: newId));
        await ref.read(downloadProgressStateProvider.notifier).remove(id);
      }

      // The plugin reports ENQUEUED to nobody, so the moved record would keep
      // the paused status of the old task until the worker happens to run.
      final current = ref.read(downloadProgressStateProvider).getById(newId);
      if (current.status.isEmpty) {
        await ref
            .read(downloadProgressStateProvider.notifier)
            .update(
              DownloadProgress(
                id: newId,
                status: DownloadStatus.pending,
                progress: progress.progress,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );
      }
    } finally {
      _resuming.remove(id);
    }
  }

  /// Starts the download behind [entry] again from scratch.
  ///
  /// The URL it was asked for is read from the native task row before that row
  /// is dropped; the refused row would otherwise be read back as live by the
  /// boot reconciliation. A record without such a row, such as one restored
  /// from a backup, falls back to the URLs kept with its post.
  ///
  /// Reports whether a replacement download was started. A false leaves the
  /// old record in place, so the user still has something to retry from.
  Future<bool> _reenqueue(DownloadEntry entry, {DownloadTask? task}) async {
    if (entry.post.isReserved) return false;

    task ??= await _taskById(entry.id);
    final url = task != null && task.url.isNotEmpty
        ? task.url
        : _postFileUrl(entry.post);
    if (url.isEmpty) {
      mainLog.w('Downloader: no URL left to restart ${entry.id}');
      return false;
    }

    if (task != null) {
      await FlutterDownloader.remove(
        taskId: entry.id,
        shouldDeleteContent: false,
      );
    }
    // Whatever the failed attempt left is either partial or not media at all.
    await _deleteLocalContent(entry.dest);

    final newId = await download(entry.post, url: url, preferCache: false);
    if (newId == null) {
      mainLog.w('Downloader: failed to restart ${entry.id}');
      return false;
    }

    // The replacement record is in place; the old one goes last so a failed
    // start above left the user something to retry from.
    await ref.read(downloadEntryStateProvider.notifier).remove(entry.id);
    return true;
  }

  /// Best URL a record still carries for itself.
  ///
  /// The original is what a download normally asks for; the smaller variants
  /// only cover a post whose original URL is empty.
  String _postFileUrl(Post post) {
    if (post.originalFile.isNotEmpty) return post.originalFile;
    if (post.sampleFile.isNotEmpty) return post.sampleFile;
    return post.previewFile;
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
    if (sharedStorageHandle.fileExists(dest)) {
      try {
        final file = File(p.join(sharedStorageHandle.path, dest));
        await file.delete();
        // The bytes are gone but the gallery keeps its row for the path, which
        // turns into a thumbnail that cannot be opened: scanning the removed
        // path is what drops it.
        await sharedStorageHandle.rescanFile(dest);
      } catch (e) {
        mainLog.e('Downloader: failed to delete $dest', e);
      }
    }

    // The metadata now describes a file that is no longer there.
    await deleteDownloadSidecar(root: sharedStorageHandle.path, dest: dest);

    // The plugin deletes the file itself while it still tracks the task, so
    // the branch above never sees it. Bumping here keeps the row from showing
    // a file that is already gone.
    ref.read(downloadFileRevisionProvider.notifier).bump();
  }

  void openFile({required String id}) {
    final entry = ref.read(downloadEntryStateProvider).getById(id);
    ref.read(sharedStorageHandleProvider).open(entry.dest);
  }
}
