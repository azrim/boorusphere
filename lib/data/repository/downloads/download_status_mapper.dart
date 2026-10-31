import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

/// Whether the plugin still holds the task, so its file can still land on disk
/// without the app being alive to record it.
bool isInFlightTask(DownloadTaskStatus status) {
  return status == DownloadTaskStatus.enqueued ||
      status == DownloadTaskStatus.running ||
      status == DownloadTaskStatus.paused;
}

/// The app's status for a native task status.
DownloadStatus downloadStatusOf(DownloadTaskStatus status) {
  return switch (status) {
    DownloadTaskStatus.undefined => DownloadStatus.empty,
    DownloadTaskStatus.enqueued => DownloadStatus.pending,
    DownloadTaskStatus.running => DownloadStatus.downloading,
    DownloadTaskStatus.complete => DownloadStatus.downloaded,
    DownloadTaskStatus.failed => DownloadStatus.failed,
    DownloadTaskStatus.canceled => DownloadStatus.canceled,
    DownloadTaskStatus.paused => DownloadStatus.paused,
  };
}
