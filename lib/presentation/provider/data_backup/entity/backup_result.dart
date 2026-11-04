import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'backup_result.freezed.dart';

@freezed
sealed class BackupResult with _$BackupResult {
  const factory BackupResult.idle() = IdleBackupResult;
  const factory BackupResult.imported(String fileName) = ImportedBackupResult;
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
