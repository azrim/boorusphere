import 'dart:io';

import 'package:archive/archive.dart';
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
  /// Downloads images from [imageUrls].
  ///
  /// When [asArchive] is true, files are bundled into a ZIP in the
  /// documents/downloads folder. When false (default), individual files
  /// are saved to the shared downloads directory.
  static Future<BatchDownloadResult> download(
    List<String> imageUrls, {
    bool asArchive = false,
  }) async {
    if (imageUrls.isEmpty) {
      return const BatchDownloadResult(
        success: false,
        error: 'No images to download',
      );
    }

    Directory? batchDir;
    try {
      final tempDir = await getTemporaryDirectory();
      batchDir = Directory(
        '${tempDir.path}/batch_download_${DateTime.now().millisecondsSinceEpoch}',
      );
      await batchDir.create(recursive: true);

      // Determine destination directory
      final destDir = asArchive
          ? '${(await getApplicationDocumentsDirectory()).path}/downloads'
          : (await _getDownloadsDir()).path;

      final downloadsDir = Directory(destDir);
      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      // Download all images in parallel
      final dio = Dio();
      final futures = <Future<void>>[];
      final fileNames = <String>[];

      for (int i = 0; i < imageUrls.length; i++) {
        final imageUrl = imageUrls[i];
        if (imageUrl.isEmpty) continue;

        final urlParts = imageUrl.split('.');
        final ext = urlParts.last.split('?').first;
        final fileName = '${i + 1}.$ext';
        fileNames.add(fileName);

        if (!asArchive) {
          // Direct mode: download straight to destination
          futures.add(dio.download(imageUrl, '${downloadsDir.path}/$fileName'));
        } else {
          // Archive mode: download to temp dir first
          futures.add(dio.download(imageUrl, '${batchDir.path}/$fileName'));
        }
      }
      await Future.wait(futures);

      if (asArchive) {
        // Encode ZIP on background isolate
        final filePaths = batchDir
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

        return BatchDownloadResult(success: true, savedPath: finalZipPath);
      } else {
        return BatchDownloadResult(
          success: true,
          savedPath: downloadsDir.path,
        );
      }
    } catch (e) {
      return BatchDownloadResult(success: false, error: e.toString());
    } finally {
      // Always clean up temp directory
      if (batchDir != null && batchDir.existsSync()) {
        batchDir.deleteSync(recursive: true);
      }
    }
  }

  static Future<Directory> _getDownloadsDir() async {
    // Use platform-specific downloads directory
    if (Platform.isAndroid) {
      // On Android, use the external storage Downloads directory
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir;
    }
    // Fallback to app documents
    return getApplicationDocumentsDirectory();
  }
}
