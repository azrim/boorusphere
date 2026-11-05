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

@freezed
sealed class BackupResult with _$BackupResult {
  const factory BackupResult.idle() = IdleBackupResult;

  /// [stores] counts what each recognized store took from the archive. A
  /// store that reports zero is a store the archive carried empty, which is
  /// why it is named instead of left out: the number is what tells an empty
  /// archive apart from an unreadable one.
  const factory BackupResult.imported(
    String fileName, {
    @Default(<BackupStore, int>{}) Map<BackupStore, int> stores,
  }) = ImportedBackupResult;
  const factory BackupResult.exported(String path) = ExportedBackupResult;
  const factory BackupResult.loading(DataBackupType type) = LoadingBackupResult;

  /// [type] names the run that failed, because the two failures need different
  /// advice: a rejected archive is the file the user picked, a failed backup is
  /// the folder the app writes to.
  const factory BackupResult.error({
    Object? error,
    StackTrace? stackTrace,
    DataBackupType? type,
  }) = ErrorBackupResult;
}
