import 'dart:io';

import 'package:archive/archive.dart';
import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/version_repo.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class BatchDownloadResult {
  const BatchDownloadResult({
    required this.success,
    this.savedPath,
    this.error,
    this.savedCount = 0,
    this.failedCount = 0,
  });

  final bool success;

  /// ZIP written for an archived batch, or the folder the files landed in.
  final String? savedPath;
  final String? error;

  /// Files that reached the disk; an archived batch counts its members.
  final int savedCount;

  /// URLs that produced no usable file.
  final int failedCount;
}

/// Runs in a background isolate: reads files from [filePaths], builds an
/// [Archive], and encodes it as ZIP. Returns null on failure.
List<int>? _encodeZip(List<String> filePaths) {
  final archive = Archive();
  for (final path in filePaths) {
    final file = File(path);
    if (file.existsSync()) {
      final data = file.readAsBytesSync();
      final fileName = path.split('/').last;
      archive.addFile(ArchiveFile(fileName, data.length, data));
    }
  }
  return ZipEncoder().encode(archive);
}

class BatchDownloadProvider {
  /// Downloads images from [imageUrls] into the shared download folder.
  ///
  /// When [asArchive] is true, the files are bundled into a ZIP written next to
  /// them. When false (default), individual files are saved to [storage].
  ///
  /// [posts] lets a request carry the Referer of the post it came from and, on
  /// top of that, gets every written file registered as a [DownloadEntry] when
  /// [ref] is supplied, so the Downloads page lists what this batch saved. An
  /// archived batch is the exception: its files only live inside the ZIP. A
  /// URL that fails, or that answers with something which is not media, is
  /// dropped and counted in [BatchDownloadResult.failedCount] instead of
  /// ending the rest of the batch.
  static Future<BatchDownloadResult> download(
    List<String> imageUrls, {
    bool asArchive = false,
    required SharedStorageHandle storage,
    WidgetRef? ref,
    List<Post>? posts,
  }) async {
    if (imageUrls.isEmpty) {
      return const BatchDownloadResult(
        success: false,
        error: 'No images to download',
      );
    }

    // Resolved while [ref] is still usable: the page can be left mid-batch,
    // and a disposed [ref] throws on read. The notifiers are keepAlive, so
    // they stay valid after the widget that started the batch is gone.
    //
    // The app client brings the cookie jar, the User-Agent and the retry
    // policy the single-download path relies on; without a [WidgetRef] it is
    // out of reach and a bare client is all that is left.
    final client = ref?.read(dioProvider) ?? Dio();
    final versionRepo = ref?.read(versionRepoProvider);
    // An archived batch keeps its files only inside the ZIP, and the folder
    // they were fetched into is deleted once it is written: recording them
    // would leave the Downloads page listing files that are not on disk.
    final entryState = asArchive
        ? null
        : ref?.read(downloadEntryStateProvider.notifier);
    final progressState = asArchive
        ? null
        : ref?.read(downloadProgressStateProvider.notifier);

    Directory? batchDir;
    try {
      await storage.init();
      final downloadsDir = Directory(storage.path);
      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      if (asArchive) {
        final tempDir = await getTemporaryDirectory();
        batchDir = Directory(
          '${tempDir.path}/batch_download_${DateTime.now().millisecondsSinceEpoch}',
        );
        await batchDir.create(recursive: true);
      }

      final targetDir = asArchive ? batchDir! : downloadsDir;
      final usedNames = <String>{};
      final downloads = <Future<bool>>[];

      for (final imageUrl in imageUrls) {
        if (imageUrl.isEmpty) continue;

        final fileName = _uniqueFileName(imageUrl, targetDir, usedNames);
        downloads.add(
          _downloadOne(
            client: client,
            url: imageUrl,
            fileName: fileName,
            destPath: '${targetDir.path}/$fileName',
            storage: storage,
            post: _findPost(imageUrl, posts),
            versionRepo: versionRepo,
            entryState: entryState,
            progressState: progressState,
          ),
        );
      }

      final results = await Future.wait(downloads);
      final savedCount = results.where((it) => it).length;
      final failedCount = results.length - savedCount;

      if (asArchive) {
        if (savedCount == 0) {
          return BatchDownloadResult(
            success: false,
            error: 'No files downloaded',
            failedCount: failedCount,
          );
        }

        final filePaths = batchDir!
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .toList();

        final zipData = await compute(_encodeZip, filePaths);
        if (zipData == null) {
          throw Exception('Failed to create ZIP archive');
        }

        final zipFileName =
            'batch_${DateTime.now().millisecondsSinceEpoch}.zip';
        final finalZipPath = '${downloadsDir.path}/$zipFileName';
        await File(finalZipPath).writeAsBytes(zipData);
        await storage.rescan();

        return BatchDownloadResult(
          success: true,
          savedPath: finalZipPath,
          savedCount: savedCount,
          failedCount: failedCount,
        );
      }

      await storage.rescan();
      if (savedCount == 0) {
        return BatchDownloadResult(
          success: false,
          error: 'No files downloaded',
          failedCount: failedCount,
        );
      }

      return BatchDownloadResult(
        success: true,
        savedPath: downloadsDir.path,
        savedCount: savedCount,
        failedCount: failedCount,
      );
    } catch (e) {
      return BatchDownloadResult(success: false, error: e.toString());
    } finally {
      // Always clean up temp directory
      if (batchDir != null && batchDir.existsSync()) {
        batchDir.deleteSync(recursive: true);
      }
    }
  }

  /// Fetches [url] into [destPath] and reports whether a media file ended up
  /// there.
  static Future<bool> _downloadOne({
    required Dio client,
    required String url,
    required String fileName,
    required String destPath,
    required SharedStorageHandle storage,
    required Post? post,
    required VersionRepo? versionRepo,
    required DownloadEntryState? entryState,
    required DownloadProgressState? progressState,
  }) async {
    try {
      await client.download(
        url,
        destPath,
        options: Options(
          // Media URLs are served through CDN redirects, while the app client
          // leaves redirects to its callers.
          followRedirects: true,
          headers: _headers(versionRepo, post, url),
        ),
      );
    } catch (e) {
      mainLog.e('BatchDownloadProvider: failed to fetch $url', e);
      return false;
    }

    if (!storage.isValidMedia(destPath)) {
      mainLog.w('BatchDownloadProvider: $url did not return media');
      _deleteQuietly(File(destPath));
      return false;
    }

    if (post != null && entryState != null && progressState != null) {
      await _registerEntry(
        entryState: entryState,
        progressState: progressState,
        post: post,
        dest: fileName,
      );
    }
    return true;
  }

  /// Request headers the single-download path sends: a booru behind hotlink
  /// protection answers with an HTML page when the User-Agent or the Referer
  /// is missing.
  static Map<String, String> _headers(
    VersionRepo? versionRepo,
    Post? post,
    String url,
  ) {
    final builder = HeadersFactory.builder();
    if (versionRepo != null) {
      builder.setUserAgent(versionRepo.current);
    }
    final postUrl = post?.postUrl ?? '';
    builder.setReferer(createReferer(postUrl.isEmpty ? url : postUrl));
    return builder.build();
  }

  /// Adds the written file to the Downloads page as a finished entry.
  ///
  /// The id is local to the app: nothing is enqueued through the platform
  /// downloader, so it only has to stay unique among entries. Each store is
  /// written on its own, so one record that fails to persist cannot stop the
  /// rest of the batch from being listed, nor turn a file already on disk into
  /// a failed download.
  static Future<void> _registerEntry({
    required DownloadEntryState entryState,
    required DownloadProgressState progressState,
    required Post post,
    required String dest,
  }) async {
    final id =
        'batch_${DateTime.now().microsecondsSinceEpoch}_${dest.hashCode}';
    try {
      await entryState.add(DownloadEntry(id: id, post: post, dest: dest));
    } catch (e) {
      mainLog.e('BatchDownloadProvider: failed to record entry $id', e);
      return;
    }
    try {
      await progressState.update(
        DownloadProgress(
          id: id,
          progress: 100,
          status: DownloadStatus.downloaded,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      mainLog.e('BatchDownloadProvider: failed to record progress $id', e);
    }
  }

  /// Post whose file is [url], so the request can carry its Referer and the
  /// written file can be recorded against it.
  static Post? _findPost(String url, List<Post>? posts) {
    if (posts == null) return null;
    for (final post in posts) {
      if (post.sampleFile == url || post.originalFile == url) return post;
    }
    return null;
  }

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      mainLog.e('BatchDownloadProvider: failed to delete ${file.path}', e);
    }
  }

  /// File name derived from [url], de-duplicated against the names already
  /// queued in this batch and the files already in [dir], so a batch never
  /// overwrites a file another download put there.
  static String _uniqueFileName(String url, Directory dir, Set<String> used) {
    final decoded = decodeComponentSafely(url.fileName);
    final sanitized = decoded.replaceAll(
      RegExp(r'([^a-zA-Z0-9\s\.\(\)_\-]+)'),
      '_',
    );
    final dot = sanitized.lastIndexOf('.');
    final stem = (dot > 0 ? sanitized.substring(0, dot) : sanitized).trim();
    final ext = dot > 0 ? sanitized.substring(dot) : '';

    var candidate = '${stem.isEmpty ? 'image' : stem}$ext';
    var suffix = 1;
    while (!used.add(candidate) ||
        File('${dir.path}/$candidate').existsSync()) {
      candidate = '${stem.isEmpty ? 'image' : stem}_${suffix++}$ext';
    }
    return candidate;
  }
}
