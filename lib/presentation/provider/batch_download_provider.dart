import 'dart:io';

import 'package:archive/archive.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class BatchDownloadResult {
  const BatchDownloadResult({
    required this.success,
    this.savedPath,
    this.error,
  });

  final bool success;
  final String? savedPath;
  final String? error;
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
  static Future<BatchDownloadResult> download(
    List<String> imageUrls, {
    bool asArchive = false,
    required SharedStorageHandle storage,
  }) async {
    if (imageUrls.isEmpty) {
      return const BatchDownloadResult(
        success: false,
        error: 'No images to download',
      );
    }

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
      final dio = Dio();
      final futures = <Future<void>>[];
      final usedNames = <String>{};

      for (final imageUrl in imageUrls) {
        if (imageUrl.isEmpty) continue;

        final fileName = _uniqueFileName(imageUrl, targetDir, usedNames);
        futures.add(dio.download(imageUrl, '${targetDir.path}/$fileName'));
      }
      await Future.wait(futures);

      if (asArchive) {
        final filePaths = batchDir!
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .toList();

        if (filePaths.isEmpty) {
          return const BatchDownloadResult(
            success: false,
            error: 'No files downloaded',
          );
        }

        final zipData = await compute(_encodeZip, filePaths);
        if (zipData == null) {
          throw Exception('Failed to create ZIP archive');
        }

        final zipFileName =
            'batch_${DateTime.now().millisecondsSinceEpoch}.zip';
        final finalZipPath = '${downloadsDir.path}/$zipFileName';
        await File(finalZipPath).writeAsBytes(zipData);
        await storage.rescan();

        return BatchDownloadResult(success: true, savedPath: finalZipPath);
      }

      await storage.rescan();
      return BatchDownloadResult(success: true, savedPath: downloadsDir.path);
    } catch (e) {
      return BatchDownloadResult(success: false, error: e.toString());
    } finally {
      // Always clean up temp directory
      if (batchDir != null && batchDir.existsSync()) {
        batchDir.deleteSync(recursive: true);
      }
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
