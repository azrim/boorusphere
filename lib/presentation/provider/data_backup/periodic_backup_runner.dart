import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_option.dart';
import 'package:boorusphere/presentation/provider/settings/periodic_backup_state.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Drives the periodic backup from the moments the app is actually running.
///
/// Nothing schedules the work while the app is closed, so the interval is
/// checked when the app boots and every time it comes back to the foreground:
/// a backup that came due while the app was away runs on the next resume.
final periodicBackupRunnerProvider = Provider<PeriodicBackupRunner>(
  PeriodicBackupRunner.new,
);

class PeriodicBackupRunner {
  PeriodicBackupRunner(this._ref);

  final Ref _ref;

  /// Set while a run is in flight. A resume can land in the middle of a slow
  /// backup, and two overlapping runs would write the same archive into the
  /// same folder while both read the same boxes.
  bool _running = false;

  /// Backs up when the setting is on and the last backup is older than the
  /// configured frequency. Safe to call on every boot and resume: it returns
  /// without touching anything when the interval has not elapsed.
  Future<void> maybeRun() async {
    if (_running) return;

    final setting = _ref.read(periodicBackupSettingStateProvider);
    if (!setting.enabled) return;

    final last = setting.lastBackupTime;
    if (last != null &&
        DateTime.now().difference(last) < setting.frequency.duration) {
      return;
    }

    final passphrase = setting.backupPassphrase;
    // An encrypted backup without its passphrase would have to fall back to a
    // plain ZIP, which puts the user's data unencrypted into a shared folder.
    if (setting.encryptBackup && passphrase.isEmpty) {
      mainLog.w(
        'PeriodicBackup: skipped, encryption is on but no passphrase is stored',
      );
      return;
    }

    _running = true;
    try {
      // The run reports its own failures and stamps the last backup time, so
      // a failed one is retried on the next resume instead of being counted
      // as done.
      await _ref
          .read(dataBackupStateProvider.notifier)
          .backup(
            option: const BackupOption(),
            passphrase: setting.encryptBackup ? passphrase : null,
          );
    } finally {
      _running = false;
    }
  }
}
