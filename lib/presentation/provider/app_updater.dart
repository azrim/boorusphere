import 'dart:io';

import 'package:boorusphere/constant/app.dart';
import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_updater.g.dart';

@riverpod
AppUpdater appUpdater(Ref ref) {
  return AppUpdater(ref);
}

@riverpod
DownloadProgress appUpdateProgress(Ref ref) {
  final id = ref.watch(appUpdaterProvider.select((it) => it.id));
  return ref.watch(downloadProgressStateProvider).getById(id);
}

class AppUpdater {
  AppUpdater(this.ref);

  final Ref ref;

  String id = '';
  String _savedDir = '';

  String _fileNameOf(AppVersion version) {
    return 'boorusphere-$version-$kAppArch.apk';
  }

  Future<void> clear() async {
    final tasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: 'SELECT * FROM task WHERE file_name LIKE \'%.apk\'');
    if (tasks == null) return;
    for (var task in tasks) {
      await ref.read(downloadEntryStateProvider.notifier).remove(task.taskId);
      await FlutterDownloader.remove(
        taskId: task.taskId,
        shouldDeleteContent: true,
      );
    }
    id = '';
  }

  Future<void> start(AppVersion version) async {
    await clear();
    final fileName = _fileNameOf(version);
    final url = version.apkUrl;

    // Use external cache directory for APK downloads
    final cacheDir = await getExternalCacheDirectories();
    final saveDir = cacheDir?.firstOrNull ?? await getTemporaryDirectory();
    _savedDir = saveDir.path;

    // Create directory if it doesn't exist
    if (!saveDir.existsSync()) {
      try {
        saveDir.createSync(recursive: true);
      } catch (_) {}
    }

    // Delete existing APK if present
    final apk = File(path.join(_savedDir, fileName));
    if (apk.existsSync()) {
      try {
        apk.deleteSync();
      } catch (_) {}
    }

    final versionRepo = ref.read(versionRepoProvider);
    final taskId = await FlutterDownloader.enqueue(
      url: url,
      fileName: fileName,
      savedDir: _savedDir,
      showNotification: true,
      openFileFromNotification: true,
      headers:
          HeadersFactory.builder().setUserAgent(versionRepo.current).build(),
    );

    if (taskId != null) {
      id = taskId;
      // Track the download entry
      final entry = DownloadEntry(
        id: taskId,
        dest: fileName,
      );
      await ref.read(downloadEntryStateProvider.notifier).add(entry);
    }
  }

  Future<void> install(AppVersion version) async {
    if (id.isEmpty) return;
    await FlutterDownloader.open(taskId: id);
  }
}
