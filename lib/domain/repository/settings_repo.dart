import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';

abstract interface class SettingsRepo {
  /// Whether changes reach the disk. False when the settings box could not be
  /// opened, in which case reads answer with defaults and writes are kept only
  /// for the running session.
  bool get isPersistent;

  T get<T>(Setting key, {required T or});
  Future<void> put<T>(Setting key, T value);

  /// Restores [src] and reports how many settings reached the store, or null
  /// when the payload is not a settings map. An empty map is zero and writes
  /// nothing: the exporter can produce one without knowing the stored values,
  /// so it is not proof that the source had no settings.
  Future<int?> import(String src);
  Future<BackupItem> export();
}
