import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_option.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_result.dart';
import 'package:boorusphere/presentation/provider/data_backup/telegram_backup_service.dart';
import 'package:boorusphere/presentation/provider/settings/periodic_backup_state.dart';
import 'package:boorusphere/presentation/screens/settings/widgets/settings_section.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:boorusphere/presentation/widgets/settings_sheet.dart';
import 'package:boorusphere/presentation/widgets/sheet_row.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

@RoutePage()
class DataBackupPage extends StatelessWidget {
  const DataBackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.dataBackup.title)),
      body: const SafeArea(child: _Content()),
    );
  }
}

class _Content extends HookConsumerWidget {
  const _Content();

  Future<bool?> _warningDialog(BuildContext context, String fileName) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.t.dataBackup.restore.title),
          icon: const Icon(Icons.restore),
          content: Text(
            context.t.dataBackup.restore.warningFile(file: fileName),
          ),
          actions: [
            TextButton(
              onPressed: () => context.navigator.pop(false),
              child: Text(context.t.cancel),
            ),
            ElevatedButton(
              onPressed: () => context.navigator.pop(true),
              child: Text(context.t.restore),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodicState = ref.watch(periodicBackupSettingStateProvider);
    final periodicNotifier = ref.read(
      periodicBackupSettingStateProvider.notifier,
    );

    // A result belongs to the run that produced it: the page opens on a
    // clean state instead of replaying the last snackbar or error. The
    // reset waits for the frame, since a provider cannot be written while
    // the widget tree is building.
    final backupNotifier = ref.read(dataBackupStateProvider.notifier);
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => backupNotifier.reset(),
      );
    }, const []);

    ref.listen<BackupResult?>(dataBackupStateProvider, (prev, next) {
      switch (next) {
        case LoadingBackupResult(:final type):
          showDialog(
            context: context,
            // The run cannot be cancelled, so a tap outside must not leave
            // the page without a report of how it ended.
            barrierDismissible: false,
            builder: (_) => UncontrolledProviderScope(
              container: ProviderScope.containerOf(context),
              child: _LoadingDialog(type: type),
            ),
          );
        case ImportedBackupResult(:final fileName):
          // The loading dialog is closed by its own listener, and a dialog
          // cannot be pushed in the frame that pops another one. Waiting for
          // the frame keeps this prompt from being dismissed with it.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => PopScope(
                canPop: false,
                child: AlertDialog(
                  icon: const Icon(Icons.restart_alt),
                  title: Text(
                    context.t.dataBackup.restore.completed(file: fileName),
                  ),
                  content: Text(context.t.dataBackup.restore.completedDesc),
                  actions: [
                    // Closing the activity is the whole point: the restored
                    // boxes are only read on a cold start, so the app has to
                    // be opened again for them to take effect.
                    ElevatedButton(
                      onPressed: SystemNavigator.pop,
                      child: Text(context.t.dataBackup.restore.restartNow),
                    ),
                  ],
                ),
              ),
            );
          });
        case ExportedBackupResult(:final path):
          context.scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(context.t.dataBackup.backup.success(dest: path)),
              duration: const Duration(seconds: 2),
            ),
          );
        case ErrorBackupResult():
          context.scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(context.t.dataBackup.restore.invalid),
              duration: const Duration(seconds: 1),
            ),
          );
        default:
      }
    });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
      children: [
        const SizedBox(height: DesignTokens.spacingMd),
        // The backup and restore rows name themselves, so they need no
        // section label of their own.
        TileGroup(
          children: [
            ListTile(
              leading: const Icon(Icons.backup),
              title: Text(context.t.dataBackup.backup.title),
              subtitle: RowSubtitle(Text(context.t.dataBackup.backup.desc)),
              onTap: () async {
                final option = await showSheet<BackupOption>(
                  context: context,
                  builder: (context) => const _BackupOptionSheet(),
                );
                if (option == null || !context.mounted) return;

                String? passphrase;
                if (option.encrypt) {
                  // A stored passphrase seals the archive without a prompt,
                  // which is what automatic backups rely on.
                  final stored = ref
                      .read(periodicBackupSettingStateProvider)
                      .backupPassphrase;
                  if (stored.isNotEmpty) {
                    passphrase = stored;
                  } else {
                    // The passphrase is asked for before the run starts:
                    // backing out of the prompt has to leave no archive
                    // behind, plain or otherwise.
                    final result = await showDialog<_PassphraseResult>(
                      context: context,
                      builder: (_) =>
                          const _PassphraseDialog(mode: _PassphraseMode.backup),
                    );
                    if (result == null) return;
                    passphrase = result.passphrase;
                    if (result.save) {
                      await ref
                          .read(periodicBackupSettingStateProvider.notifier)
                          .setPassphrase(result.passphrase);
                    }
                  }
                }

                unawaited(
                  ref
                      .read(dataBackupStateProvider.notifier)
                      .backup(option: option, passphrase: passphrase),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(context.t.dataBackup.restore.title),
              subtitle: RowSubtitle(Text(context.t.dataBackup.restore.desc)),
              onTap: () {
                ref
                    .read(dataBackupStateProvider.notifier)
                    .restore(
                      onConfirm: (fileName) =>
                          _warningDialog(context, fileName),
                      onPassphrase: () async {
                        if (!context.mounted) return null;
                        final result = await showDialog<_PassphraseResult>(
                          context: context,
                          builder: (_) => const _PassphraseDialog(
                            mode: _PassphraseMode.restore,
                          ),
                        );
                        return result?.passphrase;
                      },
                    );
              },
            ),
          ],
        ),
        SettingsSection(
          title: context.t.periodicBackup.title,
          children: [
            SwitchListTile(
              title: Text(context.t.periodicBackup.enable),
              value: periodicState.enabled,
              onChanged: periodicNotifier.setEnabled,
            ),
            _FrequencyTile(
              state: periodicState,
              notifier: periodicNotifier,
              enabled: periodicState.enabled,
            ),
            SwitchListTile(
              title: Text(context.t.periodicBackup.deleteOld),
              subtitle: RowSubtitle(
                Text(context.t.periodicBackup.deleteOldDesc),
              ),
              value: periodicState.deleteOldBackups,
              onChanged: periodicState.enabled
                  ? periodicNotifier.setDeleteOldBackups
                  : null,
            ),
            _MaxBackupSlider(
              state: periodicState,
              notifier: periodicNotifier,
              enabled: periodicState.enabled && periodicState.deleteOldBackups,
            ),
            // The switch only records a default; a backup started without a
            // stored passphrase still asks for one.
            SwitchListTile(
              title: Text(context.t.periodicBackup.encrypt),
              subtitle: RowSubtitle(
                Text(
                  periodicState.encryptBackup && !periodicNotifier.hasPassphrase
                      ? context.t.periodicBackup.encryptNeedsPassphrase
                      : context.t.periodicBackup.encryptDesc,
                ),
              ),
              value: periodicState.encryptBackup,
              onChanged: periodicNotifier.setEncryption,
            ),
            _PassphraseTile(state: periodicState, notifier: periodicNotifier),
            _LastBackupInfo(lastBackupTime: periodicState.lastBackupTime),
          ],
        ),
        SettingsSection(
          title: context.t.periodicBackup.telegram.title,
          children: [
            SwitchListTile(
              title: Text(context.t.periodicBackup.telegram.enable),
              value: periodicState.telegramEnabled,
              onChanged: periodicState.enabled
                  ? periodicNotifier.setTelegramEnabled
                  : null,
            ),
            _TelegramChatIdTile(
              state: periodicState,
              notifier: periodicNotifier,
              enabled: periodicState.enabled && periodicState.telegramEnabled,
            ),
            _TelegramBotTokenTile(
              state: periodicState,
              notifier: periodicNotifier,
              enabled: periodicState.enabled && periodicState.telegramEnabled,
            ),
            _OpenTelegramBotTile(
              enabled: periodicState.enabled && periodicState.telegramEnabled,
            ),
            _TestConnectionTile(
              enabled: periodicState.enabled && periodicState.telegramEnabled,
            ),
            _BackupNowTile(
              enabled: periodicState.enabled && periodicState.telegramEnabled,
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingLg),
      ],
    );
  }
}

class _LoadingDialog extends HookConsumerWidget {
  const _LoadingDialog({required this.type});

  final DataBackupType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(dataBackupStateProvider, (previous, next) {
      if (next is! LoadingBackupResult) {
        context.navigator.pop();
      }
    });
    // The dialog is the only progress report while the run is in flight, so
    // it stays until the result arrives: the back gesture is ignored for the
    // same reason a tap outside is.
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.all(DesignTokens.spacingMd),
              child: CircularProgressIndicator(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: DesignTokens.spacingMd),
                child: Text(
                  type == DataBackupType.backup
                      ? context.t.dataBackup.backup.loading
                      : context.t.dataBackup.restore.loading,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupOptionSheet extends HookConsumerWidget {
  const _BackupOptionSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The global switch supplies the starting value, so encryption does not
    // have to be turned on again for every backup. Toggling it here applies
    // to this run only and leaves the setting alone.
    final option = useState(
      BackupOption(
        encrypt: ref.read(periodicBackupSettingStateProvider).encryptBackup,
      ),
    );

    // One row per packable store; the row carries the tick so the state is
    // readable without aiming at the checkbox.
    Widget contentRow(
      String title,
      bool value,
      BackupOption Function(bool) apply,
    ) {
      return SheetRow(
        title: title,
        selected: value,
        trailing: Checkbox(
          value: value,
          onChanged: (v) => option.value = apply(v ?? false),
        ),
        onTap: () => option.value = apply(!value),
      );
    }

    return SheetShell(
      title: context.t.dataBackup.backup.title,
      footer: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(elevation: 0),
          onPressed: option.value.isValid()
              ? () => Navigator.pop(context, option.value)
              : null,
          child: Text(context.t.backup),
        ),
      ),
      child: SingleChildScrollView(
        child: SheetPanel(
          children: [
            contentRow(
              context.t.servers.title,
              option.value.server,
              (v) => option.value.copyWith(server: v),
            ),
            contentRow(
              context.t.searchHistory,
              option.value.searchHistory,
              (v) => option.value.copyWith(searchHistory: v),
            ),
            contentRow(
              context.t.tagsBlocker.title,
              option.value.blockedTags,
              (v) => option.value.copyWith(blockedTags: v),
            ),
            contentRow(
              context.t.favorites.title,
              option.value.favoritePost,
              (v) => option.value.copyWith(favoritePost: v),
            ),
            contentRow(
              context.t.settings.title,
              option.value.setting,
              (v) => option.value.copyWith(setting: v),
            ),
            // Encryption is not part of what gets packed, so it closes the
            // list instead of sitting among the content choices.
            SheetRow(
              title: context.t.dataBackup.encrypt,
              detail: context.t.dataBackup.encryptDesc,
              trailing: Switch(
                value: option.value.encrypt,
                onChanged: (v) =>
                    option.value = option.value.copyWith(encrypt: v),
              ),
              onTap: () => option.value = option.value.copyWith(
                encrypt: !option.value.encrypt,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which flow is asking for a passphrase.
enum _PassphraseMode {
  /// Sealing a new archive: typed twice, and it can be kept for the next
  /// automatic backup.
  backup,

  /// Opening an existing archive: typed once.
  restore,

  /// Stored in the settings: typed twice, and the stored one can be removed.
  stored,
}

/// What the passphrase dialog returns.
class _PassphraseResult {
  const _PassphraseResult(
    this.passphrase, {
    this.save = false,
    this.remove = false,
  });

  final String passphrase;

  /// Whether the passphrase should be kept for automatic backups.
  final bool save;

  /// Whether the stored passphrase should be dropped instead of replaced.
  final bool remove;
}

/// Asks for a backup passphrase.
///
/// A new passphrase is typed twice, because a typo would produce an archive
/// nobody can open. A restore asks once.
class _PassphraseDialog extends HookWidget {
  const _PassphraseDialog({required this.mode, this.canRemove = false});

  final _PassphraseMode mode;

  /// Whether the dialog offers to drop the passphrase stored in the settings.
  final bool canRemove;

  /// The shortest passphrase the backup flow accepts, so anything shorter is
  /// already known to be wrong when restoring.
  static const _minLength = 8;

  bool get _confirm => mode != _PassphraseMode.restore;

  @override
  Widget build(BuildContext context) {
    final passphrase = useTextEditingController();
    final confirmation = useTextEditingController();
    final save = useState(true);
    final error = useState<String?>(null);

    void submit() {
      final value = passphrase.text;
      if (value.length < _minLength) {
        error.value = _confirm
            ? context.t.dataBackup.passphraseTooShort(n: _minLength)
            : context.t.dataBackup.wrongPassphrase;
        return;
      }
      if (_confirm && value != confirmation.text) {
        error.value = context.t.dataBackup.passphraseMismatch;
        return;
      }
      Navigator.of(context).pop(
        _PassphraseResult(
          value,
          save: mode == _PassphraseMode.backup && save.value,
        ),
      );
    }

    return AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: Text(context.t.dataBackup.passphraseTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: passphrase,
            autofocus: true,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: _confirm
                ? TextInputAction.next
                : TextInputAction.done,
            decoration: InputDecoration(
              labelText: context.t.dataBackup.passphrase,
              helperText: context.t.dataBackup.passphraseHint(n: _minLength),
            ),
            onSubmitted: _confirm ? null : (_) => submit(),
          ),
          if (_confirm) ...[
            const SizedBox(height: DesignTokens.spacingSm),
            TextField(
              controller: confirmation,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.t.dataBackup.passphraseConfirm,
              ),
              onSubmitted: (_) => submit(),
            ),
          ],
          if (mode == _PassphraseMode.backup)
            CheckboxListTile(
              value: save.value,
              onChanged: (v) => save.value = v ?? true,
              title: Text(context.t.dataBackup.savePassphrase),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          if (error.value case final message?) ...[
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (canRemove)
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(const _PassphraseResult('', remove: true)),
            child: Text(context.t.dataBackup.passphraseRemove),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.cancel),
        ),
        ElevatedButton(
          onPressed: submit,
          child: Text(switch (mode) {
            _PassphraseMode.backup => context.t.backup,
            _PassphraseMode.restore => context.t.restore,
            _PassphraseMode.stored => context.t.save,
          }),
        ),
      ],
    );
  }
}

String frequencyLabel(BuildContext context, BackupFrequency frequency) {
  return switch (frequency) {
    BackupFrequency.daily => context.t.periodicBackup.frequencyDaily,
    BackupFrequency.weekly => context.t.periodicBackup.frequencyWeekly,
    BackupFrequency.monthly => context.t.periodicBackup.frequencyMonthly,
  };
}

class _FrequencyTile extends StatelessWidget {
  const _FrequencyTile({
    required this.state,
    required this.notifier,
    this.enabled = true,
  });

  final PeriodicBackupState state;
  final PeriodicBackupSettingState notifier;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.frequency),
      subtitle: RowSubtitle(Text(frequencyLabel(context, state.frequency))),
      onTap: enabled
          ? () async {
              final picked = await showChoiceSheet<BackupFrequency>(
                context: context,
                title: context.t.periodicBackup.frequency,
                selected: state.frequency,
                choices: BackupFrequency.values
                    .map(
                      (it) =>
                          Choice(value: it, label: frequencyLabel(context, it)),
                    )
                    .toList(),
              );
              if (picked == null) return;
              await notifier.setFrequency(picked.value);
            }
          : null,
    );
  }
}

class _MaxBackupSlider extends HookWidget {
  const _MaxBackupSlider({
    required this.state,
    required this.notifier,
    this.enabled = true,
  });

  final PeriodicBackupState state;
  final PeriodicBackupSettingState notifier;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final sliderValue = useState(state.maxBackupCount.toDouble());

    return SettingsSliderTile(
      title: context.t.periodicBackup.maxBackups,
      value: sliderValue.value,
      valueLabel: '${sliderValue.value.round()}',
      min: 1,
      max: 10,
      divisions: 9,
      enabled: enabled,
      onChanged: (value) => sliderValue.value = value,
      onChangeEnd: (value) => notifier.setMaxBackupCount(value.round()),
    );
  }
}

/// Shows whether a passphrase is kept for automatic backups, and edits it.
///
/// The value itself is never rendered: the tile reports only that one exists.
class _PassphraseTile extends StatelessWidget {
  const _PassphraseTile({required this.state, required this.notifier});

  final PeriodicBackupState state;
  final PeriodicBackupSettingState notifier;

  @override
  Widget build(BuildContext context) {
    final hasPassphrase = notifier.hasPassphrase;

    return ListTile(
      leading: const Icon(Icons.key),
      title: Text(context.t.dataBackup.passphraseTile),
      subtitle: RowSubtitle(
        Text(
          hasPassphrase ? '••••••••' : context.t.dataBackup.passphraseNotSet,
        ),
      ),
      onTap: () async {
        final result = await showDialog<_PassphraseResult>(
          context: context,
          builder: (_) => _PassphraseDialog(
            mode: _PassphraseMode.stored,
            canRemove: hasPassphrase,
          ),
        );
        if (result == null) return;
        await notifier.setPassphrase(result.remove ? '' : result.passphrase);
      },
    );
  }
}

class _LastBackupInfo extends StatelessWidget {
  const _LastBackupInfo({required this.lastBackupTime});

  final DateTime? lastBackupTime;

  String _formatLastBackup(BuildContext context, DateTime? time) {
    if (time == null) return context.t.periodicBackup.never;
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return context.t.periodicBackup.justNow;
    if (diff.inMinutes < 60) {
      return context.t.periodicBackup.minutesAgo(n: diff.inMinutes);
    }
    if (diff.inHours < 24) {
      return context.t.periodicBackup.hoursAgo(n: diff.inHours);
    }
    return context.t.periodicBackup.daysAgo(n: diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(context.t.periodicBackup.lastBackup),
      subtitle: RowSubtitle(Text(_formatLastBackup(context, lastBackupTime))),
    );
  }
}

class _TelegramChatIdTile extends HookWidget {
  const _TelegramChatIdTile({
    required this.state,
    required this.notifier,
    this.enabled = true,
  });

  final PeriodicBackupState state;
  final PeriodicBackupSettingState notifier;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.telegram.chatId),
      subtitle: Text(
        state.telegramChatId.isEmpty
            ? context.t.periodicBackup.telegram.notSet
            : state.telegramChatId,
      ),
      onTap: enabled
          ? () async {
              final result = await showTextSheet(
                context: context,
                title: context.t.periodicBackup.telegram.chatId,
                hint: context.t.periodicBackup.telegram.chatIdHint,
                initialValue: state.telegramChatId,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                ],
                saveLabel: context.t.save,
                cancelLabel: context.t.cancel,
              );
              if (result != null) {
                await notifier.setTelegramChatId(result);
              }
            }
          : null,
    );
  }
}

class _TelegramBotTokenTile extends HookWidget {
  const _TelegramBotTokenTile({
    required this.state,
    required this.notifier,
    this.enabled = true,
  });

  final PeriodicBackupState state;
  final PeriodicBackupSettingState notifier;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.telegram.botToken),
      subtitle: Text(
        state.telegramBotToken.isEmpty
            ? context.t.periodicBackup.telegram.notSet
            : '••••••••${state.telegramBotToken.substring(state.telegramBotToken.length > 8 ? state.telegramBotToken.length - 8 : 0)}',
      ),
      onTap: enabled
          ? () async {
              final result = await showTextSheet(
                context: context,
                title: context.t.periodicBackup.telegram.botToken,
                hint: context.t.periodicBackup.telegram.botTokenHint,
                initialValue: state.telegramBotToken,
                saveLabel: context.t.save,
                cancelLabel: context.t.cancel,
              );
              if (result != null) {
                await notifier.setTelegramBotToken(result);
              }
            }
          : null,
    );
  }
}

class _OpenTelegramBotTile extends StatelessWidget {
  const _OpenTelegramBotTile({this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.telegram.openBot),
      subtitle: RowSubtitle(
        Text(context.t.periodicBackup.telegram.openBotDesc),
      ),
      trailing: const Icon(Icons.open_in_new),
      onTap: enabled
          ? () async {
              final uri = Uri.parse('https://t.me/BotFather');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          : null,
    );
  }
}

class _TestConnectionTile extends HookConsumerWidget {
  const _TestConnectionTile({this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = useState(false);

    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.telegram.testConnection),
      trailing: isLoading.value
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send),
      onTap: !enabled || isLoading.value
          ? null
          : () async {
              isLoading.value = true;
              final TelegramResult result;
              try {
                result = await ref
                    .read(telegramBackupServiceProvider.notifier)
                    .testConnection();
              } finally {
                // The spinner is the only feedback while this runs, so it has
                // to clear even when the request throws.
                isLoading.value = false;
              }

              if (!context.mounted) return;

              final message = switch (result) {
                TelegramResult.success =>
                  context.t.periodicBackup.telegram.testSuccess,
                TelegramResult.invalidToken =>
                  context.t.periodicBackup.telegram.invalidToken,
                TelegramResult.invalidChatId =>
                  context.t.periodicBackup.telegram.invalidChatId,
                TelegramResult.networkError =>
                  context.t.periodicBackup.telegram.networkError,
                _ => context.t.periodicBackup.telegram.unknownError,
              };

              context.scaffoldMessenger.showSnackBar(
                SnackBar(content: Text(message)),
              );
            },
    );
  }
}

class _BackupNowTile extends HookConsumerWidget {
  const _BackupNowTile({this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = useState(false);
    final settings = ref.watch(periodicBackupSettingStateProvider);
    final isConfigured =
        settings.telegramChatId.isNotEmpty &&
        settings.telegramBotToken.isNotEmpty;

    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.telegram.backupNow),
      subtitle: RowSubtitle(
        Text(context.t.periodicBackup.telegram.backupNowDesc),
      ),
      trailing: isLoading.value
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_upload),
      onTap: !enabled || !isConfigured || isLoading.value
          ? null
          : () async {
              isLoading.value = true;
              try {
                final backupFile = await ref
                    .read(dataBackupStateProvider.notifier)
                    .createBackupForTelegram();

                if (backupFile == null) {
                  if (context.mounted) {
                    context.scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          context.t.periodicBackup.telegram.backupFailed,
                        ),
                      ),
                    );
                  }
                  return;
                }

                final result = await ref
                    .read(telegramBackupServiceProvider.notifier)
                    .sendBackupFile(backupFile);

                if (result == TelegramResult.success) {
                  await ref
                      .read(periodicBackupSettingStateProvider.notifier)
                      .setLastBackupTime(DateTime.now());
                }

                if (!context.mounted) return;

                final message = result == TelegramResult.success
                    ? context.t.periodicBackup.telegram.backupSent
                    : context.t.periodicBackup.telegram.backupFailed;

                context.scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text(message)),
                );
              } finally {
                // The spinner is the only feedback while this runs, so it has
                // to clear even when the backup throws.
                isLoading.value = false;
              }
            },
    );
  }
}
