import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'flutter_downloader_handle.g.dart';

@Riverpod(keepAlive: true)
FlutterDownloaderHandle downloaderHandle(Ref ref) {
  final handle = FlutterDownloaderHandle();
  ref.onDispose(handle.dispose);
  return handle;
}

@pragma('vm:entry-point')
class FlutterDownloaderHandle {
  FlutterDownloaderHandle() {
    // A mapping left by an earlier handle would send the plugin callbacks to
    // a port nothing listens to any more.
    _removeNameMapping();
    IsolateNameServer.registerPortWithName(receiver.sendPort, _name);
    FlutterDownloader.registerCallback(_onProgressUpdated);
  }

  final receiver = ReceivePort();
  StreamSubscription<dynamic>? _subscription;

  /// Starts forwarding plugin callbacks to [onUpdate].
  ///
  /// A [ReceivePort] takes one listener for its whole life, so a second call
  /// keeps the first listener instead of throwing.
  void listen(void Function(DownloadProgress progress) onUpdate) {
    if (_subscription != null) return;
    _subscription = receiver.listen((data) {
      if (data is! List || data.length < 3) return;
      final id = data[0];
      final status = data[1];
      final progress = data[2];
      if (id is! String ||
          status is! int ||
          status < 0 ||
          status >= DownloadStatus.values.length ||
          progress is! int) {
        return;
      }
      final normalizedProgress = (progress < 0 || progress > 100)
          ? (status == DownloadStatus.downloaded.index ? 100 : -1)
          : progress;
      onUpdate(
        DownloadProgress(
          id: id,
          status: DownloadStatus.values[status],
          progress: normalizedProgress,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  void dispose() {
    _removeNameMapping();
    _subscription?.cancel();
    _subscription = null;
    receiver.close();
  }

  static const _name = 'DownloaderHandle';

  static void _removeNameMapping() {
    if (IsolateNameServer.lookupPortByName(_name) != null) {
      IsolateNameServer.removePortNameMapping(_name);
    }
  }

  @pragma('vm:entry-point')
  static void _onProgressUpdated(String id, int status, int progress) {
    IsolateNameServer.lookupPortByName(_name)?.send([id, status, progress]);
  }
}
