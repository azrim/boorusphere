import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'backup_result.freezed.dart';

/// The stores an archive can carry, in the order a restore report lists them.
///
/// The archive keys stay with their repositories; this is the screen's
/// vocabulary for the same six stores.
enum BackupStore {
  servers,
  blockedTags,
  favorites,
  settings,
  searchHistory,
  downloads,
}

/// Why a run was refused before it could touch a box or the backups folder.
///
/// Separate from the run type: "a failed backup" describes the folder, while
/// this describes a session in which the boxes cannot hold what a run would
/// write.
enum BackupFailure { storageUnavailable }

@freezed
sealed class BackupResult with _$BackupResult {
  const factory BackupResult.idle() = IdleBackupResult;

  /// [stores] counts what each recognized store took from the archive. A
  /// store that reports zero is a store the archive carried empty, which is
  /// why it is named instead of left out: the number is what tells an empty
  /// archive apart from an unreadable one.
  ///
  /// [failed] names the stores that carried a payload but could not be
  /// applied, or whose box refused the write. A run with both lists is a
  /// partial restore: the successful stores are already on disk, so the
  /// screen still owes the restart the complete case asks for.
  const factory BackupResult.imported(
    String fileName, {
    @Default(<BackupStore, int>{}) Map<BackupStore, int> stores,
    @Default(<BackupStore>[]) List<BackupStore> failed,
  }) = ImportedBackupResult;
  const factory BackupResult.exported(String path) = ExportedBackupResult;
  const factory BackupResult.loading(DataBackupType type) = LoadingBackupResult;

  /// [type] names the run that failed, because the two failures need different
  /// advice: a rejected archive is the file the user picked, a failed backup is
  /// the folder the app writes to. [failure] is set when nothing was attempted
  /// at all, which reads differently from a run that tried and lost.
  const factory BackupResult.error({
    Object? error,
    StackTrace? stackTrace,
    DataBackupType? type,
    BackupFailure? failure,
  }) = ErrorBackupResult;
}
