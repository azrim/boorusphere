import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/presentation/utils/extensions/flutter_downloader.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadTaskStatusExt.toDownloadStatus', () {
    test('enqueued maps to pending', () {
      expect(
        DownloadTaskStatus.enqueued.toDownloadStatus(),
        DownloadStatus.pending,
      );
    });

    test('running maps to downloading', () {
      expect(
        DownloadTaskStatus.running.toDownloadStatus(),
        DownloadStatus.downloading,
      );
    });

    test('complete maps to downloaded', () {
      expect(
        DownloadTaskStatus.complete.toDownloadStatus(),
        DownloadStatus.downloaded,
      );
    });

    test('failed maps to failed', () {
      expect(
        DownloadTaskStatus.failed.toDownloadStatus(),
        DownloadStatus.failed,
      );
    });

    test('canceled maps to canceled', () {
      expect(
        DownloadTaskStatus.canceled.toDownloadStatus(),
        DownloadStatus.canceled,
      );
    });

    test('paused maps to paused', () {
      expect(
        DownloadTaskStatus.paused.toDownloadStatus(),
        DownloadStatus.paused,
      );
    });
  });

  group('DownloadStatus getters', () {
    test('isPending', () {
      expect(DownloadStatus.pending.isPending, isTrue);
      expect(DownloadStatus.downloading.isPending, isFalse);
    });

    test('isDownloading', () {
      expect(DownloadStatus.downloading.isDownloading, isTrue);
    });

    test('isDownloaded', () {
      expect(DownloadStatus.downloaded.isDownloaded, isTrue);
    });

    test('isFailed', () {
      expect(DownloadStatus.failed.isFailed, isTrue);
    });

    test('isCanceled', () {
      expect(DownloadStatus.canceled.isCanceled, isTrue);
    });

    test('isPaused', () {
      expect(DownloadStatus.paused.isPaused, isTrue);
    });

    test('isEmpty', () {
      expect(DownloadStatus.empty.isEmpty, isTrue);
    });
  });
}
