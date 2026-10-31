import 'package:boorusphere/data/repository/downloads/download_status_mapper.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

extension DownloadTaskStatusExt on DownloadTaskStatus {
  DownloadStatus toDownloadStatus() => downloadStatusOf(this);
}
