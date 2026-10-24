import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/data/repository/search_history/user_search_history.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/booru_tags_blocker_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_option.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_result.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/search_history_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/download_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/periodic_backup_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'data_backup.g.dart';

typedef BackupItem = MapEntry<String, Object>;

enum DataBackupType { backup, restore }

@riverpod
class DataBackupState extends _$DataBackupState {
  @override
  BackupResult build() {
    return const BackupResult.idle();
  }

  Future<Directory> _tempDir() async {
    final basedir = await getTemporaryDirectory();
    final temp = Directory(path.join(basedir.path, '.backup.tmp'));
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
    temp.createSync();
    return temp;
  }

  Future<Directory> _backupDir() async {
    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);
    if (!await sharedStorageHandle.init()) {
      throw StateError('shared storage is not writable');
    }
    return sharedStorageHandle.createSubDir('backups');
  }

  Future<BackupItem> _metadata() async {
    final versionRepo = ref.read(versionRepoProvider);
    return BackupItem(appId, {'version': '${versionRepo.current}'});
  }

  void _invalidateProviders() {
    ref.invalidate(serverStateProvider);
    ref.invalidate(tagsBlockerStateProvider);
    ref.invalidate(searchHistoryStateProvider);
    ref.invalidate(favoritePostStateProvider);
    ref.invalidate(uiSettingStateProvider);
    ref.invalidate(contentSettingStateProvider);
    ref.invalidate(downloadSettingStateProvider);
    ref.invalidate(serverSettingStateProvider);
  }

  Future<void> restore({Future<bool?> Function()? onConfirm}) async {
    try {
      await _restore(onConfirm: onConfirm);
    } on Object catch (e, stack) {
      // A corrupt or truncated archive throws out of the decoder, and a failed
      // import throws out of the repository. Either way the screen must get a
      // terminal state instead of an unhandled error.
      mainLog.e('DataBackupState: restore failed', e, stack);
      state = const BackupResult.error();
    }
  }

  Future<void> _restore({Future<bool?> Function()? onConfirm}) async {
    final backupsDir = await _backupDir();
    await FilePicker.clearTemporaryFiles();

    final picked = await FilePicker.pickFile(
      initialDirectory: backupsDir.absolute.path,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    final path = picked?.path;
    if (path == null) {
      state = const BackupResult.idle();
      return;
    }
    final stream = InputFileStream(path);
    try {
      final decoder = ZipDecoder().decodeStream(stream);
      const maxDecompressedSize = 100 * 1024 * 1024; // 100MB
      final totalSize = decoder.files
          .where((it) => it.isFile)
          .fold<int>(0, (sum, file) => sum + file.size);
      if (totalSize > maxDecompressedSize) {
        state = const BackupResult.error();
        return;
      }
      if (!decoder.files.any((it) => it.name == '$appId.json')) {
        state = const BackupResult.error();
        return;
      }

      final confirm = onConfirm ?? () async => true;
      final continueRestore = await confirm.call() ?? false;
      if (!continueRestore) {
        state = const BackupResult.idle();
        return;
      }

      state = const BackupResult.loading(DataBackupType.restore);
      for (final json in decoder.files.where((it) => it.isFile)) {
        final content = utf8.decode(json.content);
        switch (json.name.replaceAll('.json', '')) {
          case UserServerRepo.key:
            await ref.read(serverRepoProvider).import(content);
            break;
          case BooruTagsBlockerRepo.boxKey:
            await ref.read(tagsBlockerRepoProvider).import(content);
            break;
          case UserFavoritePostRepo.key:
            await ref.read(favoritePostRepoProvider).import(content);
            break;
          case UserSettingsRepo.key:
            await ref.read(settingsRepoProvider).import(content);
            break;
          case UserSearchHistoryRepo.key:
            await ref.read(searchHistoryRepoProvider).import(content);
            break;
          default:
            break;
        }
      }

      _invalidateProviders();
      state = const BackupResult.imported();
    } finally {
      await stream.close();
    }
  }

  Future<void> backup({BackupOption option = const BackupOption()}) async {
    if (!option.isValid()) return;

    state = const BackupResult.loading(DataBackupType.backup);
    try {
      final zipFile = await _createBackupFile(option);
      if (zipFile == null) {
        state = const BackupResult.error();
        return;
      }
      // A manual backup is a backup like any other, so it owns the same
      // readout the periodic one updates.
      await ref
          .read(periodicBackupSettingStateProvider.notifier)
          .setLastBackupTime(DateTime.now());
      state = BackupResult.exported(zipFile.path);
    } on Object catch (e, stack) {
      // Writing the archive or copying it into the shared folder can fail
      // (no space, folder not writable). Leaving the state at `loading` would
      // keep the screen blocked forever.
      mainLog.e('DataBackupState: backup failed', e, stack);
      state = const BackupResult.error();
    }
  }

  /// Creates a backup file and returns it. Used for both local and Telegram backups.
  Future<File?> _createBackupFile(BackupOption option) async {
    if (!option.isValid()) return null;

    final server = ref.read(serverRepoProvider).export();
    final blockedTags = ref.read(tagsBlockerRepoProvider).export();
    final favoritePost = ref.read(favoritePostRepoProvider).export();
    final setting = ref.read(settingsRepoProvider).export();
    final searchHistory = ref.read(searchHistoryRepoProvider).export();
    final temp = await _tempDir();
    final zipPath = path.join(temp.path, 'data.zip');
    try {
      final encoder = ZipFileEncoder()..create(zipPath);

      final entries = [
        _metadata(),
        if (option.server) server,
        if (option.blockedTags) blockedTags,
        if (option.favoritePost) favoritePost,
        if (option.setting) setting,
        if (option.searchHistory) searchHistory,
      ];

      await Future.wait(
        entries.map((entry) async {
          final item = await entry;
          final data = item.value;
          if (data is List && data.isEmpty) return;

          final file = File('${temp.path}/${item.key}.json');
          await file.writeAsString(jsonEncode(data));
          return encoder.addFile(file);
        }),
      );

      await encoder.close();

      final dir = await _backupDir();
      final time = DateFormat('yyyy-MM-dd-HH-mm-ss').format(DateTime.now());
      final name = '${appId}_backup_$time.zip';
      final zip = File(path.join(dir.path, name));
      if (zip.existsSync()) {
        zip.deleteSync();
      }

      await File(zipPath).copy(zip.path);
      await ref.read(sharedStorageHandleProvider).rescan();
      return zip;
    } finally {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
  }

  /// Creates a backup and returns the file path for external use (e.g., Telegram)
  Future<File?> createBackupForTelegram() async {
    return _createBackupFile(const BackupOption());
  }

  static const appId = 'boorusphere';
}
