import 'package:freezed_annotation/freezed_annotation.dart';

part 'backup_option.freezed.dart';

@freezed
abstract class BackupOption with _$BackupOption {
  const factory BackupOption({
    @Default(true) bool searchHistory,
    @Default(true) bool server,
    @Default(true) bool blockedTags,
    @Default(true) bool favoritePost,
    @Default(true) bool setting,
    // Off by default: the records describe what someone downloaded, which is
    // more sensitive than the settings an automatic backup already carries.
    @Default(false) bool downloadRecords,
    @Default(false) bool encrypt,
  }) = _BackupOption;
}

extension BackupOptionX on BackupOption {
  bool isValid() =>
      searchHistory ||
      server ||
      blockedTags ||
      favoritePost ||
      setting ||
      downloadRecords;

  /// Whether this run carries every store the scheduled backup writes.
  ///
  /// Only such a run may advance the schedule's clock: a subset archive leaves
  /// the stores it skipped without a fresh copy, so letting it postpone the
  /// next scheduled run would keep them stale for up to a whole interval.
  /// Download records are not part of the scheduled set, so they do not count.
  bool get coversScheduledStores =>
      server && blockedTags && favoritePost && setting && searchHistory;
}
