import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'periodic_backup_state.freezed.dart';
part 'periodic_backup_state.g.dart';

enum BackupFrequency {
  daily,
  weekly,
  monthly;

  String get label {
    switch (this) {
      case BackupFrequency.daily:
        return 'Every day';
      case BackupFrequency.weekly:
        return 'Every week';
      case BackupFrequency.monthly:
        return 'Every month';
    }
  }

  Duration get duration {
    switch (this) {
      case BackupFrequency.daily:
        return const Duration(days: 1);
      case BackupFrequency.weekly:
        return const Duration(days: 7);
      case BackupFrequency.monthly:
        return const Duration(days: 30);
    }
  }

  static BackupFrequency fromIndex(int index) {
    if (index < 0 || index >= BackupFrequency.values.length) {
      return BackupFrequency.daily;
    }
    return BackupFrequency.values[index];
  }
}

@freezed
class PeriodicBackupState with _$PeriodicBackupState {
  const factory PeriodicBackupState({
    @Default(false) bool enabled,
    @Default(BackupFrequency.daily) BackupFrequency frequency,
    @Default(true) bool deleteOldBackups,
    @Default(3) int maxBackupCount,
    DateTime? lastBackupTime,
    @Default(false) bool telegramEnabled,
    @Default('') String telegramChatId,
    @Default('') String telegramBotToken,
  }) = _PeriodicBackupState;
}

@riverpod
class PeriodicBackupSettingState extends _$PeriodicBackupSettingState {
  @override
  PeriodicBackupState build() {
    final repo = ref.read(settingsRepoProvider);
    final lastBackupMs =
        repo.get<int?>(Setting.periodicBackupLastTime, or: null);
    return PeriodicBackupState(
      enabled: repo.get(Setting.periodicBackupEnabled, or: false),
      frequency: BackupFrequency.fromIndex(
        repo.get(Setting.periodicBackupFrequency, or: 0),
      ),
      deleteOldBackups: repo.get(Setting.periodicBackupDeleteOld, or: true),
      maxBackupCount: repo.get(Setting.periodicBackupMaxCount, or: 3),
      lastBackupTime: lastBackupMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastBackupMs)
          : null,
      telegramEnabled: repo.get(Setting.telegramBackupEnabled, or: false),
      telegramChatId: repo.get(Setting.telegramChatId, or: ''),
      telegramBotToken: repo.get(Setting.telegramBotToken, or: ''),
    );
  }

  Future<void> setEnabled(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(enabled: value);
    await repo.put(Setting.periodicBackupEnabled, value);
  }

  Future<void> setFrequency(BackupFrequency value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(frequency: value);
    await repo.put(Setting.periodicBackupFrequency, value.index);
  }

  Future<void> setDeleteOldBackups(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(deleteOldBackups: value);
    await repo.put(Setting.periodicBackupDeleteOld, value);
  }

  Future<void> setMaxBackupCount(int value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(maxBackupCount: value);
    await repo.put(Setting.periodicBackupMaxCount, value);
  }

  Future<void> setLastBackupTime(DateTime? value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(lastBackupTime: value);
    await repo.put(
      Setting.periodicBackupLastTime,
      value?.millisecondsSinceEpoch,
    );
  }

  Future<void> setTelegramEnabled(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(telegramEnabled: value);
    await repo.put(Setting.telegramBackupEnabled, value);
  }

  Future<void> setTelegramChatId(String value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(telegramChatId: value);
    await repo.put(Setting.telegramChatId, value);
  }

  Future<void> setTelegramBotToken(String value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(telegramBotToken: value);
    await repo.put(Setting.telegramBotToken, value);
  }

  bool get isTelegramConfigured =>
      state.telegramChatId.isNotEmpty && state.telegramBotToken.isNotEmpty;
}
