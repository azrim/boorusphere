import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';

/// Raised at boot when the settings box is not open, so the app is running on
/// in-memory defaults and nothing changed in this session survives a restart.
class SettingsUnavailableException implements Exception {
  const SettingsUnavailableException();

  @override
  String toString() => 'The settings box is not open; defaults are in use.';
}

abstract interface class SettingsRepo {
  /// Whether changes reach the disk. False when the settings box could not be
  /// opened, in which case reads answer with defaults and writes are kept only
  /// for the running session.
  bool get isPersistent;

  T get<T>(Setting key, {required T or});
  Future<void> put<T>(Setting key, T value);
  Future<void> import(String src);
  Future<BackupItem> export();
}
