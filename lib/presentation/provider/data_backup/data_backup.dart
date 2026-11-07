import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/downloads/user_download_repo.dart';
import 'package:boorusphere/data/repository/fallback_box.dart';
import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/data/repository/search_history/user_search_history.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/booru_tags_blocker_repo.dart';
import 'package:boorusphere/data/repository/video_cache/video_cache.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/app_lock/app_lock_state.dart';
import 'package:boorusphere/presentation/provider/data_backup/archive_name.dart';
import 'package:boorusphere/presentation/provider/data_backup/backup_cipher.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_option.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_result.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
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

  /// Whether a run may write right now.
  ///
  /// A stand-in box and the missing settings box keep their values for this
  /// session only. A backup written from them would say "the source held
  /// nothing" for a store that was merely unreadable, and a restore reported
  /// from them would name stores the forced restart discards. Both are
  /// refused instead of half-written.
  bool get storageAvailable =>
      degradedBoxNames.isEmpty && ref.read(settingsRepoProvider).isPersistent;

  /// Whether another run owns the boxes and the backups folder. A caller that
  /// asked for a new run reads this to say why nothing started.
  bool get isBusy => _busy;

  /// Whether [storeKey] is bound to a box that cannot persist this session.
  bool _storeUnavailable(String storeKey) {
    if (storeKey == UserSettingsRepo.key) {
      return !ref.read(settingsRepoProvider).isPersistent;
    }
    if (storeKey == UserDownloadsRepo.entryKey) {
      // Both download boxes are replaced together, but the progress box is
      // what a record's status is written to, so either name means the store
      // is degraded.
      return isDegradedBox(UserDownloadsRepo.entryKey) ||
          isDegradedBox(UserDownloadsRepo.progressKey);
    }
    return isDegradedBox(storeKey);
  }

  /// The two failures the screen can report. Each names its own run, so a
  /// backup that could not be written never reads like a corrupt archive.
  static const BackupResult restoreError = BackupResult.error(
    type: DataBackupType.restore,
  );
  static const BackupResult backupError = BackupResult.error(
    type: DataBackupType.backup,
  );

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
    ref.invalidate(downloadEntryStateProvider);
    ref.invalidate(downloadProgressStateProvider);
    // The restored rows point at paths whose files were just checked, so the
    // memoized answer of every existing row has to be read again.
    ref.read(downloadFileRevisionProvider.notifier).bump();
    // The video cache reads its budget once, when the provider is built, and
    // is kept alive so the player and the settings screen share one instance.
    // A restore that carried a different budget therefore has to be handed to
    // the running cache: invalidating the provider instead would orphan the
    // downloads it has in flight, whose index write would land after a fresh
    // instance already read the file.
    await _applyRestoredCacheBudget();
    // The list is rebuilt from the restored box. A failure here is not a
    // failed restore: every store is already written, and turning that into
    // an "invalid archive" report would hide the data that did land.
    try {
      await ref.read(serverStateProvider.notifier).populate();
    } on Object catch (e, stack) {
      mainLog.w('DataBackupState: failed to reload the server list', e, stack);
    }
  }

  /// Gives the running video cache the budget the restored settings name.
  ///
  /// A failure here is not a failed restore: the boxes are already written, and
  /// the cache simply keeps the budget it booted with until the next launch.
  Future<void> _applyRestoredCacheBudget() async {
    try {
      final stored = ref
          .read(settingsRepoProvider)
          .get(Setting.videoCacheMaxBytes, or: VideoCache.defaultMaxBytes);
      await ref
          .read(videoCacheProvider)
          .applyMaxBytes(VideoCache.budgetFrom(stored));
    } on Object catch (e, stack) {
      mainLog.w('DataBackupState: restored cache budget not applied', e, stack);
    }
  }

  /// Runs a restore and reports whether it was accepted.
  ///
  /// False means another run owns the boxes: nothing was asked, nothing was
  /// read and nothing changed, so the caller can say so instead of leaving the
  /// tap unanswered. A run that started and failed answers true here; its
  /// outcome arrives through [state].
  Future<bool> restore({
    Future<bool?> Function(String fileName)? onConfirm,
    Future<String?> Function()? onPassphrase,
  }) async {
    if (_busy) return false;
    _busy = true;
    try {
      await _restore(onConfirm: onConfirm, onPassphrase: onPassphrase);
    } on Object catch (e, stack) {
      // A corrupt or truncated archive throws out of the decoder, and a failed
      // import throws out of the repository. Either way the screen must get a
      // terminal state instead of an unhandled error.
      mainLog.e('DataBackupState: restore failed', e, stack);
      // The states mirroring the boxes already written are refreshed by the
      // import loop before it rethrows.
      state = restoreError;
    } finally {
      _busy = false;
    }
    return true;
  }

  Future<void> _restore({
    Future<bool?> Function(String fileName)? onConfirm,
    Future<String?> Function()? onPassphrase,
  }) async {
    // Restoring reads a file the user picks, so it does not depend on the
    // shared folder being writable.
    await FilePicker.clearTemporaryFiles();

    // Any file is accepted: the picker turns allowedExtensions into MIME
    // types on Android, and an .enc archive has none, which leaves it
    // greyed out and unselectable. What the file is gets decided below, from
    // its header rather than its name.
    //
    // The picker covers the app with a system activity, which the lifecycle
    // reports as a pause. Tell the lock this trip is still part of the session
    // so an immediate timeout does not greet the user with the lock screen on
    // the way back.
    final lock = ref.read(appLockProvider.notifier);
    lock.beginExternalFlow();
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.any);
    } finally {
      lock.endExternalFlow();
    }

    final pickedPath = picked?.path;
    if (pickedPath == null) {
      state = const BackupResult.idle();
      return;
    }

    final fileName = path.basename(pickedPath);

    // Confirming follows the picker: a run cancelled at the picker never had
    // anything to overwrite, so the prompt only appears once there is an
    // archive to apply. The prompt gets the archive name, because the picker
    // lists every file and the newest one sits at the top.
    final confirm = onConfirm ?? (_) async => true;
    final continueRestore = await confirm.call(fileName) ?? false;
    if (!continueRestore) {
      state = const BackupResult.idle();
      return;
    }

    state = const BackupResult.loading(DataBackupType.restore);
    // The dialog is opened by a listener, so it only exists after the next
    // frame. Handing control back to the event loop here is what lets that
    // frame be drawn before the decryption and the import loop take over.
    await Future<void>.delayed(Duration.zero);

    final pickedFile = File(pickedPath);
    // Read the size from the file system first: the cap below exists to keep
    // the bytes out of memory, so testing it after `readAsBytes` would only
    // describe the crash. The picker accepts any file on purpose, which puts
    // a video or an ISO one tap away from this screen.
    final size = await pickedFile.length();
    if (size > _maxArchiveSize) {
      state = restoreError;
      return;
    }
    var bytes = await pickedFile.readAsBytes();
    // The file can change between the stat and the read; the second check
    // costs nothing and keeps the guard true.
    if (bytes.length > _maxArchiveSize) {
      state = restoreError;
      return;
    }

    // The envelope header decides, not the extension: an encrypted archive
    // renamed to .zip still asks for its passphrase, and a plain one renamed
    // to .enc still restores.
    final encrypted = BackupCipher.isEncrypted(bytes);
    if (encrypted) {
      // The passphrase is always asked for, even when one is stored: the
      // archive may come from another device, so a key kept here says nothing
      // about this file. The stored passphrase only seals new backups.
      final askPassphrase = onPassphrase;
      if (askPassphrase == null) {
        state = restoreError;
        return;
      }
      final passphrase = await askPassphrase();
      if (passphrase == null) {
        // Dismissing the prompt cancels the restore instead of failing it.
        state = const BackupResult.idle();
        return;
      }
      try {
        bytes = await BackupCipher.decryptAsync(bytes, passphrase);
      } on BackupCipherException {
        // A wrong passphrase is a user mistake: the screen gets an error
        // result, and the passphrase itself is never logged.
        state = restoreError;
        return;
      }
    } else if (!_isZipArchive(bytes)) {
      // Without the extension filter, any file the user picks can land here.
      // Only a ZIP can be handed to the decoder; anything else is reported
      // instead of being thrown out of it.
      state = restoreError;
      return;
    }

    final decoder = ZipDecoder().decodeBytes(bytes);
    const maxDecompressedSize = 100 * 1024 * 1024; // 100MB
    final totalSize = decoder.files
        .where((it) => it.isFile)
        .fold<int>(0, (sum, file) => sum + file.size);
    if (totalSize > maxDecompressedSize) {
      state = restoreError;
      return;
    }
    // The marker entry is what identifies the archive as ours; its content
    // is not read, so a backup written by another build still restores.
    final hasMarker = decoder.files.any((it) => it.name == '$appId.json');
    if (!hasMarker) {
      state = restoreError;
      return;
    }

    // The six stores an archive can carry, each with the reader that applies
    // its payload. A file whose name matches none of them is not ours to read.
    final stores = <String, (BackupStore, Future<int?> Function(String))>{
      UserServerRepo.key: (
        BackupStore.servers,
        ref.read(serverRepoProvider).import,
      ),
      BooruTagsBlockerRepo.boxKey: (
        BackupStore.blockedTags,
        ref.read(tagsBlockerRepoProvider).import,
      ),
      UserFavoritePostRepo.key: (
        BackupStore.favorites,
        ref.read(favoritePostRepoProvider).import,
      ),
      UserSettingsRepo.key: (
        BackupStore.settings,
        ref.read(settingsRepoProvider).import,
      ),
      UserSearchHistoryRepo.key: (
        BackupStore.searchHistory,
        ref.read(searchHistoryRepoProvider).import,
      ),
      UserDownloadsRepo.entryKey: (
        BackupStore.downloads,
        ref.read(downloadsRepoProvider).import,
      ),
    };

    // A store the archive carries can only be applied when its box can keep
    // what is written. A stand-in box (or the missing settings box) holds the
    // rows for this session only, and the restart this screen demands would
    // throw them away: the report would name stores that never survived.
    final carried = <String>{
      for (final file in decoder.files)
        if (file.isFile && path.dirname(file.name) == '.')
          path.basenameWithoutExtension(file.name),
    };
    final blocked = carried
        .where(stores.containsKey)
        .where(_storeUnavailable)
        .toList();
    if (blocked.isNotEmpty) {
      mainLog.w(
        'DataBackupState: restore refused, unavailable stores: $blocked',
      );
      state = const BackupResult.error(
        type: DataBackupType.restore,
        failure: BackupFailure.storageUnavailable,
      );
      return;
    }

    final imported = <BackupStore, int>{};
    final failed = <BackupStore>[];
    try {
      for (final json in decoder.files.where((it) => it.isFile)) {
        // Only the entries the exporter wrote at the root are ours; a
        // folder prefix means the archive was packed by something else.
        if (path.dirname(json.name) != '.') continue;
        final entry = stores[path.basenameWithoutExtension(json.name)];
        if (entry == null) continue;

        // A store answers null for a payload it does not recognize. That
        // store is left out of the report instead of being counted as done.
        // A payload or a write that throws must not abort the stores after
        // it: the ones before are already on disk, and the report has to name
        // both outcomes instead of calling the whole file invalid.
        try {
          final count = await entry.$2(utf8.decode(json.content));
          if (count == null) {
            failed.add(entry.$1);
          } else {
            imported[entry.$1] = count;
          }
        } on Object catch (e, stack) {
          mainLog.e(
            'DataBackupState: store "${entry.$1.name}" failed',
            e,
            stack,
          );
          failed.add(entry.$1);
        }
      }
    } finally {
      // The entries imported before a failure are already on disk, so the
      // states mirroring those boxes are refreshed on both outcomes.
      await _invalidateProviders();
    }

    // Every store the archive named was unreadable, so reporting a restore
    // would be a lie. A store that was read and held nothing counts as
    // imported: zero rows are still an answer.
    if (imported.isEmpty) {
      state = restoreError;
      return;
    }

    // The log carries counts only: the entries hold logins and API keys,
    // which stay out of it.
    if (imported.containsKey(BackupStore.servers)) {
      final servers = ref.read(serverRepoProvider).servers;
      final withCredentials = servers.where((it) => it.hasCredentials).length;
      mainLog.i(
        'Restore "$fileName" (${encrypted ? 'encrypted' : 'plain'}): '
        '${servers.length} servers, $withCredentials with credentials',
      );
    }

    state = BackupResult.imported(fileName, stores: imported, failed: failed);
  }

  /// Runs a backup and reports whether it was accepted.
  ///
  /// False means another run owns the boxes or the caller asked for nothing:
  /// no archive was attempted. A run that started answers true, and its
  /// outcome arrives through [state].
  Future<bool> backup({
    BackupOption option = const BackupOption(),
    String? passphrase,
  }) async {
    if (!option.isValid()) return false;
    if (_busy) return false;
    if (!storageAvailable) {
      // Nothing is attempted: a write into a stand-in would describe a store
      // the next start cannot read, and pruning with default settings could
      // delete archives the user chose to keep.
      state = const BackupResult.error(
        type: DataBackupType.backup,
        failure: BackupFailure.storageUnavailable,
      );
      return true;
    }
    _busy = true;

    state = const BackupResult.loading(DataBackupType.backup);
    // See the note in _restore: the progress dialog has to be painted before
    // the work starts, or the screen looks frozen instead.
    await Future<void>.delayed(Duration.zero);
    try {
      final backupFile = await _createBackupFile(
        option,
        passphrase: passphrase,
      );
      if (backupFile == null) {
        state = backupError;
        return true;
      }
      // The schedule's clock only advances on a run that carries every store
      // it is responsible for: a settings-only archive must not postpone the
      // next full one by up to a whole interval.
      if (option.coversScheduledStores) {
        await ref
            .read(periodicBackupSettingStateProvider.notifier)
            .setLastBackupTime(DateTime.now());
      }
      state = BackupResult.exported(backupFile.path);
    } on Object catch (e, stack) {
      // Writing the archive or copying it into the shared folder can fail
      // (no space, folder not writable). Leaving the state at `loading` would
      // keep the screen blocked forever.
      mainLog.e('DataBackupState: backup failed', e, stack);
      state = backupError;
    } finally {
      _busy = false;
    }
    return true;
  }

  /// Creates a backup file and returns it. Used for both local and Telegram
  /// backups.
  ///
  /// With a [passphrase] the archive is published as an encrypted envelope
  /// (`.enc`); without one it stays a plain ZIP (`.zip`).
  Future<File?> _createBackupFile(
    BackupOption option, {
    String? passphrase,
  }) async {
    if (!option.isValid()) return null;
    // See `storageAvailable`: an archive built from stand-ins would report
    // empty stores the user never chose to empty, and the prune that follows
    // would run on defaults. The Telegram path reaches this too.
    if (!storageAvailable) {
      mainLog.w('DataBackupState: backup refused, storage is unavailable');
      return null;
    }

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
        // The archive carries the records, never the media: a library of a
        // few gigabytes would neither fit the maximum size nor survive an
        // upload. A restored record whose file is missing offers a redownload.
        if (option.downloadRecords) ref.read(downloadsRepoProvider).export(),
      ];

      await Future.wait(
        entries.map((entry) async {
          final item = await entry;
          // An empty store is still written: its presence is what tells a
          // restore that the source had nothing there, instead of leaving the
          // target's old data behind as if the choice had never been made.
          final file = File('${temp.path}/${item.key}.json');
          await file.writeAsString(jsonEncode(item.value));
          return encoder.addFile(file);
        }),
      );

      await encoder.close();

      // The archive is sealed as one blob, so the ZIP is built first and its
      // ciphertext is what gets published.
      final encrypted = passphrase != null && passphrase.isNotEmpty;
      var payload = File(zipPath);
      if (encrypted) {
        final sealed = await BackupCipher.encryptAsync(
          await payload.readAsBytes(),
          passphrase,
        );
        payload = File(path.join(temp.path, 'data.enc'));
        await payload.writeAsBytes(sealed, flush: true);
      }

      final dir = await _backupDir();
      final time = DateFormat('yyyy-MM-dd-HH-mm-ss').format(DateTime.now());
      // A name is chosen from what the folder already holds: two runs in the
      // same second used to delete each other's archive, and the only copy the
      // user kept was whichever run finished last.
      final backup = freeArchiveFile(dir, time, encrypted ? 'enc' : 'zip');
      await payload.copy(backup.path);
      _pruneBackups(dir, keep: backup);
      await ref.read(sharedStorageHandleProvider).rescan();
      return backup;
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
    // Defaults are not a policy: with the settings box unreadable, the delete
    // switch and the count below would be the app's fallbacks, not the user's
    // choices, and the archives they describe are still on disk.
    if (!settings.isPersistent) return;
    if (!settings.get(Setting.periodicBackupDeleteOld, or: true)) return;

    // The archive this run just wrote counts towards the limit and is never
    // a candidate: reporting a backup whose file was then removed would be
    // wrong, and a non-positive limit leaves nothing to prune against.
    final max = settings.get(Setting.periodicBackupMaxCount, or: 3);
    if (max <= 0) return;

    try {
      final archives =
          dir
              .listSync()
              .whereType<File>()
              .where((it) => isArchiveName(path.basename(it.path)))
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

  /// Creates a backup and returns the file path for external use (e.g.,
  /// Telegram).
  ///
  /// The archive follows the same sealing rule as the scheduled run: with
  /// encryption on it is written with the stored passphrase, and a run that
  /// cannot be sealed is refused instead of uploaded plain. Nothing asks for
  /// the passphrase here, so a plain archive would be the only copy the user
  /// ever sees — and the one that leaves the device.
  ///
  /// It claims the same busy flag a local run does: both write into one folder
  /// and read the same boxes, and an overlap buries the other's result.
  Future<File?> createBackupForTelegram() async {
    if (_busy) return null;
    _busy = true;
    try {
      final setting = ref.read(periodicBackupSettingStateProvider);
      final sealing = setting.encryptBackup;
      // An encrypted run with nothing stored to seal with could only send the
      // plain archive, so it is refused instead.
      if (sealing && setting.backupPassphrase.isEmpty) return null;
      return await _createBackupFile(
        const BackupOption(),
        passphrase: sealing ? setting.backupPassphrase : null,
      );
    } finally {
      _busy = false;
    }
  }

  static const appId = archiveAppId;

  /// Upper bound for a picked archive. Nothing this app writes comes close,
  /// so a bigger file is not one of ours and is refused before it is read
  /// into memory.
  static const _maxArchiveSize = 100 * 1024 * 1024;

  /// Whether [bytes] starts with a ZIP signature: a local file header, or the
  /// end-of-central-directory record of an empty archive.
  static bool _isZipArchive(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final isZip = bytes[0] == 0x50 && bytes[1] == 0x4b;
    return isZip &&
        ((bytes[2] == 0x03 && bytes[3] == 0x04) ||
            (bytes[2] == 0x05 && bytes[3] == 0x06));
  }
}
