import 'dart:io';

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
import 'package:boorusphere/presentation/provider/download/downloader.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How far a running batch has got: [done] files settled out of [total], and
/// [fraction] of the whole batch that has arrived. A settled file counts as
/// arrived, so the bar still ends at 1 when a URL failed.
typedef BatchDownloadProgress = ({int done, int total, double fraction});

class BatchDownloadResult {
  const BatchDownloadResult({
    required this.success,
    this.error,
    this.savedCount = 0,
    this.failedCount = 0,
  });

  final bool success;
  final String? error;

  /// Files that reached the disk.
  final int savedCount;

  /// URLs that produced no usable file.
  final int failedCount;
}

class BatchDownloadProvider {
  /// Downloads [imageUrls] into the shared download folder, one file per URL.
  ///
  /// [posts] lets a request carry the Referer of the post it came from and, on
  /// top of that, gets every written file registered as a [DownloadEntry] when
  /// [ref] is supplied, so the Downloads page lists what this batch saved. A
  /// URL that fails, or that answers with something which is not media, is
  /// dropped and counted in [BatchDownloadResult.failedCount] instead of
  /// ending the rest of the batch.
  ///
  /// [onProgress] is called as the batch advances, throttled to changes worth
  /// a repaint: the caller may be rebuilding a UI with it.
  static Future<BatchDownloadResult> download(
    List<String> imageUrls, {
    required SharedStorageHandle storage,
    WidgetRef? ref,
    List<Post>? posts,
    void Function(BatchDownloadProgress progress)? onProgress,
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
    final entryState = ref?.read(downloadEntryStateProvider.notifier);
    final progressState = ref?.read(downloadProgressStateProvider.notifier);
    // The batch shares the single-download path's names, so a file queued
    // here cannot land on the path of one started from the post viewer (the
    // native worker appends to an existing file instead of replacing it).
    final downloader = ref?.read(downloaderProvider);

    try {
      await storage.init();
      final downloadsDir = Directory(storage.path);
      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final urls = imageUrls.where((it) => it.isNotEmpty).toList();
      final usedNames = <String>{};
      final downloads = <Future<String?>>[];

      // One fraction per queued file: the batch runs them side by side, so a
      // single "current file" would jump around as they settle.
      final fractions = List<double>.filled(urls.length, 0);
      var settled = 0;
      var lastFraction = -1.0;
      var lastSettled = -1;

      void report() {
        final sum = fractions.fold<double>(0, (total, it) => total + it);
        final fraction = urls.isEmpty
            ? 0.0
            : (sum / urls.length).clamp(0.0, 1.0);
        // A progress that moves by less than a hundredth of the batch is not
        // worth a rebuild of the bar.
        if (settled == lastSettled && (fraction - lastFraction).abs() < 0.01) {
          return;
        }
        lastFraction = fraction;
        lastSettled = settled;
        onProgress?.call((
          done: settled,
          total: urls.length,
          fraction: fraction,
        ));
      }

      report();

      for (var i = 0; i < urls.length; i++) {
        final index = i;
        final imageUrl = urls[i];
        // Claimed through the downloader when one is reachable: the same
        // registry the single downloads use, so both never resolve to the
        // same file. Without a [ref] only this batch can collide, and its own
        // set covers that.
        final fileName =
            downloader?.claimFileName(imageUrl) ??
            _uniqueFileName(imageUrl, downloadsDir, usedNames);
        downloads.add(
          _downloadOne(
            client: client,
            url: imageUrl,
            fileName: fileName,
            destPath: '${downloadsDir.path}/$fileName',
            storage: storage,
            post: _findPost(imageUrl, posts),
            versionRepo: versionRepo,
            entryState: entryState,
            progressState: progressState,
            onReceiveProgress: (received, total) {
              if (total <= 0) return;
              fractions[index] = (received / total).clamp(0.0, 1.0);
              report();
            },
          ).whenComplete(() {
            downloader?.releaseName(fileName);
            settled++;
            fractions[index] = 1;
            report();
          }),
        );
      }

      final results = await Future.wait(downloads);
      final saved = results.whereType<String>().toList();
      final failedCount = results.length - saved.length;

      await Future.wait(saved.map(storage.rescanFile));
      if (saved.isEmpty) {
        return BatchDownloadResult(
          success: false,
          error: 'No files downloaded',
          failedCount: failedCount,
        );
      }

      return BatchDownloadResult(
        success: true,
        savedCount: saved.length,
        failedCount: failedCount,
      );
    } catch (e) {
      return BatchDownloadResult(success: false, error: e.toString());
    }
  }

  /// Fetches [url] into [destPath] and reports the name of the media file that
  /// ended up there, or null when the URL produced no usable file.
  static Future<String?> _downloadOne({
    required Dio client,
    required String url,
    required String fileName,
    required String destPath,
    required SharedStorageHandle storage,
    required Post? post,
    required VersionRepo? versionRepo,
    required DownloadEntryState? entryState,
    required DownloadProgressState? progressState,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    try {
      await client.download(
        url,
        destPath,
        onReceiveProgress: onReceiveProgress,
        options: Options(
          // Media URLs are served through CDN redirects, while the app client
          // leaves redirects to its callers.
          followRedirects: true,
          headers: _headers(versionRepo, post, url),
        ),
      );
    } catch (e) {
      mainLog.e('BatchDownloadProvider: failed to fetch $url', e);
      return null;
    }

    if (!storage.isValidMedia(destPath)) {
      mainLog.w('BatchDownloadProvider: $url did not return media');
      _deleteQuietly(File(destPath));
      return null;
    }

    if (post != null && entryState != null && progressState != null) {
      await _registerEntry(
        entryState: entryState,
        progressState: progressState,
        post: post,
        dest: fileName,
      );
    }
    return fileName;
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
