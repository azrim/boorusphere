import 'package:boorusphere/data/repository/downloads/download_status_mapper.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/presentation/screens/downloads/download_filter.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every native status has an app status', () {
    final expected = {
      DownloadTaskStatus.undefined: DownloadStatus.empty,
      DownloadTaskStatus.enqueued: DownloadStatus.pending,
      DownloadTaskStatus.running: DownloadStatus.downloading,
      DownloadTaskStatus.complete: DownloadStatus.downloaded,
      DownloadTaskStatus.failed: DownloadStatus.failed,
      DownloadTaskStatus.canceled: DownloadStatus.canceled,
      DownloadTaskStatus.paused: DownloadStatus.paused,
    };

    for (final status in DownloadTaskStatus.values) {
      expect(downloadStatusOf(status), expected[status], reason: '$status');
    }
  });

  test('a paused task can still land on disk without the app', () {
    expect(isInFlightTask(DownloadTaskStatus.paused), isTrue);
    expect(isInFlightTask(DownloadTaskStatus.complete), isFalse);
    expect(isInFlightTask(DownloadTaskStatus.failed), isFalse);
    expect(isInFlightTask(DownloadTaskStatus.canceled), isFalse);
  });

  test('the paused filter selects only paused rows', () {
    expect(DownloadFilter.paused.toStatus(), DownloadStatus.paused);
    expect(DownloadFilter.downloading.toStatus(), DownloadStatus.downloading);
    expect(DownloadFilter.failed.toStatus(), DownloadStatus.failed);
    expect(DownloadFilter.downloaded.toStatus(), DownloadStatus.downloaded);
    expect(DownloadFilter.none.toStatus(), isNull);
  });
}
