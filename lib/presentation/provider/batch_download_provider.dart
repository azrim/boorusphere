import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class BatchDownloadResult {
  const BatchDownloadResult({
    required this.success,
    this.zipPath,
    this.error,
  });

  final bool success;
  final String? zipPath;
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
  static Future<BatchDownloadResult> download(List<String> imageUrls) async {
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

      // Download all images in parallel
      final dio = Dio();
      final futures = <Future<void>>[];
      for (int i = 0; i < imageUrls.length; i++) {
        final imageUrl = imageUrls[i];
        if (imageUrl.isEmpty) continue;

        final urlParts = imageUrl.split('.');
        final ext = urlParts.last.split('?').first;
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        final filePath = '${batchDir.path}/$fileName';

        futures.add(dio.download(imageUrl, filePath));
      }
      await Future.wait(futures);

      // Encode ZIP on background isolate
      final filePaths =
          batchDir
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

      // Save ZIP to documents/downloads
      final documentsDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${documentsDir.path}/downloads');
      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final zipFileName =
          'batch_${DateTime.now().millisecondsSinceEpoch}.zip';
      final finalZipPath = '${downloadsDir.path}/$zipFileName';
      await File(finalZipPath).writeAsBytes(zipData);

      return BatchDownloadResult(success: true, zipPath: finalZipPath);
    } catch (e) {
      return BatchDownloadResult(success: false, error: e.toString());
    } finally {
      // Always clean up temp directory
      if (batchDir != null && batchDir.existsSync()) {
        batchDir.deleteSync(recursive: true);
      }
    }
  }
}
