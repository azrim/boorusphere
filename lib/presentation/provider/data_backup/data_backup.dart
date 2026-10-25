import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/data/repository/search_history/user_search_history.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
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
import 'package:boorusphere/presentation/provider/settings/gesture_setting_state.dart';
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

/// Kept alive for the session: a backup or a restore outlives the page that
/// started it, and an auto-disposed notifier would throw on the first write
/// back to [state] while the boxes are already half-written.
@Riverpod(keepAlive: true)
class DataBackupState extends _$DataBackupState {
  /// Set while a run is in flight. The page can start a second one (the
  /// loading dialog is dismissible, and "Backup now" is a separate entry
  /// point), and two overlapping runs would overwrite each other's result
  /// while both read and write the same boxes and the same shared folder.
  bool _busy = false;

  @override
  BackupResult build() {
    return const BackupResult.idle();
  }

  /// Clears the result of a finished run, so the page does not reopen on a
  /// stale snackbar or error. A run still in flight keeps its state and the
  /// dialog that reports it.
  void reset() {
    if (_busy || state is IdleBackupResult) return;
    state = const BackupResult.idle();
  }

  /// A folder of its own for every run: two backups writing the same paths
  /// delete each other's files, and the archive that survives is whichever
  /// run finished last.
  Future<Directory> _tempDir() async {
    final basedir = await getTemporaryDirectory();
    final temp = Directory(
      path.join(
        basedir.path,
        '.backup-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    temp.createSync(recursive: true);
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

  /// Rebuilds every state that mirrors a box the restore may have replaced.
  ///
  /// [ServerState.build] starts from an empty list and is filled by
  /// [ServerState.populate], so the server list is repopulated instead of
  /// invalidated: an invalidated list would stay empty for the rest of the
  /// session.
  Future<void> _invalidateProviders() async {
    ref.invalidate(tagsBlockerStateProvider);
    ref.invalidate(searchHistoryStateProvider);
    ref.invalidate(favoritePostStateProvider);
    ref.invalidate(uiSettingStateProvider);
    ref.invalidate(contentSettingStateProvider);
    ref.invalidate(downloadSettingStateProvider);
    ref.invalidate(serverSettingStateProvider);
    ref.invalidate(gestureSettingStateProvider);
    ref.invalidate(periodicBackupSettingStateProvider);
    await ref.read(serverStateProvider.notifier).populate();
  }

  Future<void> restore({Future<bool?> Function()? onConfirm}) async {
    if (_busy) return;
    _busy = true;
    try {
      await _restore(onConfirm: onConfirm);
    } on Object catch (e, stack) {
      // A corrupt or truncated archive throws out of the decoder, and a failed
      // import throws out of the repository. Either way the screen must get a
      // terminal state instead of an unhandled error.
      mainLog.e('DataBackupState: restore failed', e, stack);
      // The states mirroring the boxes already written are refreshed by the
      // import loop before it rethrows.
      state = const BackupResult.error();
    } finally {
      _busy = false;
    }
  }

  Future<void> _restore({Future<bool?> Function()? onConfirm}) async {
    // Restoring reads a file the user picks, so it does not depend on the
    // shared folder being writable.
    await FilePicker.clearTemporaryFiles();

    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    final pickedPath = picked?.path;
    if (pickedPath == null) {
      state = const BackupResult.idle();
      return;
    }
    final stream = InputFileStream(pickedPath);
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
      // The marker entry is what identifies the archive as ours; its content
      // is not read, so a backup written by another build still restores.
      final hasMarker = decoder.files.any((it) => it.name == '$appId.json');
      if (!hasMarker) {
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
      var applied = 0;
      try {
        for (final json in decoder.files.where((it) => it.isFile)) {
          // Only the entries the exporter wrote at the root are ours; a
          // folder prefix means the archive was packed by something else.
          if (path.dirname(json.name) != '.') continue;
          final content = utf8.decode(json.content);
          switch (path.basenameWithoutExtension(json.name)) {
            case UserServerRepo.key:
              await ref.read(serverRepoProvider).import(content);
              applied++;
              break;
            case BooruTagsBlockerRepo.boxKey:
              await ref.read(tagsBlockerRepoProvider).import(content);
              applied++;
              break;
            case UserFavoritePostRepo.key:
              await ref.read(favoritePostRepoProvider).import(content);
              applied++;
              break;
            case UserSettingsRepo.key:
              await ref.read(settingsRepoProvider).import(content);
              applied++;
              break;
            case UserSearchHistoryRepo.key:
              await ref.read(searchHistoryRepoProvider).import(content);
              applied++;
              break;
            default:
              break;
          }
        }
      } finally {
        // The entries imported before a failure are already on disk, so the
        // states mirroring those boxes are refreshed on both outcomes.
        await _invalidateProviders();
      }

      // Nothing was imported, so reporting a restore would be a lie.
      if (applied == 0) {
        state = const BackupResult.error();
        return;
      }

      state = const BackupResult.imported();
    } finally {
      await stream.close();
    }
  }

  Future<void> backup({BackupOption option = const BackupOption()}) async {
    if (!option.isValid()) return;
    if (_busy) return;
    _busy = true;

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
    } finally {
      _busy = false;
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
      _pruneBackups(dir, keep: zip);
      await ref.read(sharedStorageHandleProvider).rescan();
      return zip;
    } finally {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
  }

  /// Drops the oldest archives once there are more than the configured count.
  ///
  /// Only files this app named are considered, so a file the user dropped in
  /// the folder is never deleted. The timestamp in the name sorts
  /// chronologically, which is what makes "newest first" a plain string sort.
  void _pruneBackups(Directory dir, {required File keep}) {
    final settings = ref.read(settingsRepoProvider);
    if (!settings.get(Setting.periodicBackupDeleteOld, or: true)) return;

    // The archive this run just wrote counts towards the limit and is never
    // a candidate: reporting a backup whose file was then removed would be
    // wrong, and a non-positive limit leaves nothing to prune against.
    final max = settings.get(Setting.periodicBackupMaxCount, or: 3);
    if (max <= 0) return;

    final pattern = RegExp('^${appId}_backup_.+\\.zip\$');
    try {
      final archives =
          dir
              .listSync()
              .whereType<File>()
              .where((it) => pattern.hasMatch(path.basename(it.path)))
              .where((it) => it.path != keep.path)
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));

      for (final file in archives.skip(max - 1)) {
        file.deleteSync();
      }
    } catch (e) {
      mainLog.w('DataBackupState: failed to prune old backups', e);
    }
  }

  /// Creates a backup and returns the file path for external use (e.g., Telegram)
  Future<File?> createBackupForTelegram() async {
    return _createBackupFile(const BackupOption());
  }

  static const appId = 'boorusphere';
}
