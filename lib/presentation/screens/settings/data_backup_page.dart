import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/pigeon/app_env.pi.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_option.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_result.dart';
import 'package:boorusphere/presentation/provider/data_backup/passphrase_input.dart';
import 'package:boorusphere/presentation/provider/data_backup/telegram_backup_service.dart';
import 'package:boorusphere/presentation/provider/settings/periodic_backup_state.dart';
import 'package:boorusphere/presentation/screens/settings/widgets/settings_section.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/block_checkbox_tile.dart';
import 'package:boorusphere/presentation/widgets/confirm_destructive.dart';
import 'package:boorusphere/presentation/widgets/field_decoration.dart';
import 'package:boorusphere/presentation/widgets/in_block_note.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:boorusphere/presentation/widgets/sectioned_list.dart';
import 'package:boorusphere/presentation/widgets/settings_sheet.dart';
import 'package:boorusphere/presentation/widgets/sheet_row.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// The mask a stored secret shows as. A fixed run of bullets, so the value
/// never reaches the screen and its length cannot be read off the dots.
const String _kSecretMask = '••••••••';

/// How many trailing characters of a token stay visible, enough to tell two
/// saved tokens apart without showing one.
const int _kSecretTail = 8;

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
    return confirmDestructive(
      context,
      icon: Icons.restore,
      title: context.t.dataBackup.restore.title,
      message: context.t.dataBackup.restore.warningFile(file: fileName),
      confirmLabel: context.t.restore,
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
        case ImportedBackupResult(:final fileName, :final stores):
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
                  content: _RestoreReport(stores: stores),
                  actions: [
                    // Closing the activity is the whole point: the restored
                    // boxes are only read on a cold start, so the app has to
                    // be opened again for them to take effect. There is
                    // deliberately no "Later": staying open would keep showing
                    // the data that was just replaced, with no way left to
                    // reload it, so the only honest choice here is the one that
                    // ends the session.
                    //
                    // The activity is finished from the native side. A back
                    // request cannot do it: this dialog's own PopScope is what
                    // tells the engine the framework handles back, so the
                    // request was swallowed by the dialog that made it, which
                    // left restart as a dead end. The reply is allowed to fail
                    // silently, since the activity may be gone before it
                    // crosses the channel.
                    FilledButton(
                      onPressed: () {
                        unawaited(
                          AppEnv().exitApp().catchError((Object _) {
                            // The activity can be gone before the reply lands.
                          }),
                        );
                      },
                      child: Text(context.t.dataBackup.restore.restartNow),
                    ),
                  ],
                ),
              ),
            );
          });
        case ExportedBackupResult(:final path):
          showToast(context, context.t.dataBackup.backup.success(dest: path));
        case ErrorBackupResult(:final type):
          // The two runs fail for different reasons, so each gets its own
          // line: a rejected file talks about the file, a failed backup talks
          // about where the app writes.
          showToast(
            context,
            type == DataBackupType.backup
                ? context.t.dataBackup.backup.failed
                : context.t.dataBackup.restore.invalid,
          );
        default:
      }
    });

    return SectionedList(
      children: [
        // The backup and restore rows name themselves, so they need no
        // section label of their own. The gap a heading would have made is
        // added by hand instead, so the block starts where the labelled ones
        // do.
        const SizedBox(height: DesignTokens.spacingLg),
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
                    final result = await showSheet<_PassphraseResult>(
                      context: context,
                      builder: (_) =>
                          const _PassphraseSheet(mode: _PassphraseMode.backup),
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
              // The arrow means "put these values back" everywhere else in the
              // app that offers a reset, and this row does not do that: it
              // hands the choice to the file picker. The dialog that follows
              // keeps the arrow, because there the verb is the one being
              // confirmed.
              leading: const Icon(Icons.folder_open),
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
                        final result = await showSheet<_PassphraseResult>(
                          context: context,
                          builder: (_) => const _PassphraseSheet(
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
            // Everything under this switch answers to it. The reason is said
            // while it is off, so the greyed rows have an explanation next to
            // the one control that unlocks them.
            if (!periodicState.enabled)
              InBlockNote(text: context.t.periodicBackup.turnOnForSchedule),
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
            // This switch is off limits until periodic backups run, and the
            // rows under it go grey with it. One line says which switch
            // unlocks the whole group.
            if (!periodicState.enabled)
              InBlockNote(text: context.t.periodicBackup.telegram.turnOnFirst),
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
      ],
    );
  }
}

/// What a completed restore actually wrote, store by store.
///
/// The counts are the point. An archive that carried no servers and one whose
/// servers could not be read both leave the list alone; only the number says
/// which of the two happened.
class _RestoreReport extends StatelessWidget {
  const _RestoreReport({required this.stores});

  final Map<BackupStore, int> stores;

  String _label(BuildContext context, BackupStore store) => switch (store) {
    BackupStore.servers => context.t.servers.title,
    BackupStore.blockedTags => context.t.tagsBlocker.title,
    BackupStore.favorites => context.t.favorites.title,
    BackupStore.settings => context.t.settings.title,
    BackupStore.searchHistory => context.t.searchHistory,
    BackupStore.downloads => context.t.dataBackup.downloadRecords,
  };

  @override
  Widget build(BuildContext context) {
    // A fixed order, so the report reads the same no matter how the archive
    // that produced it happened to be packed.
    final ordered = stores.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t.dataBackup.restore.completedDesc),
        for (final entry in ordered)
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
            child: Row(
              children: [
                Expanded(child: Text(_label(context, entry.key))),
                Text(
                  '${entry.value}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
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
      BackupOption Function(bool) apply, {
      String? detail,
    }) {
      return SheetRow(
        title: title,
        detail: detail,
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
        child: FilledButton(
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
            contentRow(
              context.t.dataBackup.downloadRecords,
              option.value.downloadRecords,
              (v) => option.value.copyWith(downloadRecords: v),
              detail: context.t.dataBackup.downloadRecordsDesc,
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

/// What the passphrase sheet returns.
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

/// A rejected passphrase, with the field that has to carry the reason.
class _FieldError {
  const _FieldError(this.message, {this.onConfirmation = false});

  final String message;

  /// True when the mismatch belongs under the repeated line rather than the
  /// first one.
  final bool onConfirmation;
}

/// Asks for a backup passphrase.
///
/// A new passphrase is typed twice, because a typo would produce an archive
/// nobody can open. A restore asks once.
///
/// A sheet, like every other credential the page edits: the page stays behind
/// it, and the form is one surface rather than a dialog that invents its own
/// arrangement of the same two fields.
class _PassphraseSheet extends HookWidget {
  const _PassphraseSheet({required this.mode, this.canRemove = false});

  final _PassphraseMode mode;

  /// Whether the sheet offers to drop the passphrase stored in the settings.
  final bool canRemove;

  /// The shortest passphrase the backup flow accepts, so anything shorter is
  /// already known to be wrong when restoring.
  static const _minLength = 8;

  bool get _confirm => mode != _PassphraseMode.restore;

  @override
  Widget build(BuildContext context) {
    final passphrase = useTextEditingController();
    final confirmation = useTextEditingController();
    final passphraseFocus = useFocusNode();
    final confirmationFocus = useFocusNode();
    final showPassphrase = useState(false);
    final save = useState(true);
    // The rejection and the line it belongs to: the reason has to sit on the
    // field that caused it, so a reader hears that field refuse its own value
    // rather than finding a loose sentence under the form.
    final error = useState<_FieldError?>(null);

    void submit() {
      // Normalized here, once: this is the string that both seals the archive
      // and gets stored, so the passphrase the settings report as saved is the
      // one that opens it.
      final value = preparePassphrase(passphrase.text, confirm: _confirm);
      final repeated = preparePassphrase(confirmation.text, confirm: _confirm);
      if (value.length < _minLength) {
        error.value = _FieldError(
          _confirm
              ? context.t.dataBackup.passphraseTooShort(n: _minLength)
              : context.t.dataBackup.wrongPassphrase,
        );
        passphraseFocus.requestFocus();
        return;
      }
      if (_confirm && value != repeated) {
        error.value = _FieldError(
          context.t.dataBackup.passphraseMismatch,
          onConfirmation: true,
        );
        confirmationFocus.requestFocus();
        return;
      }
      Navigator.of(context).pop(
        _PassphraseResult(
          value,
          save: mode == _PassphraseMode.backup && save.value,
        ),
      );
    }

    return SheetShell(
      title: context.t.dataBackup.passphraseTitle,
      // One action, and the sheet's own close control is the way out: a Cancel
      // button was a third exit taking width from the only action that matters.
      // Dropping the stored passphrase is a different answer, not a second way
      // to leave, so it stays a button of its own.
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: submit,
              child: Text(switch (mode) {
                _PassphraseMode.backup => context.t.backup,
                _PassphraseMode.restore => context.t.restore,
                _PassphraseMode.stored => context.t.save,
              }),
            ),
          ),
          if (canRemove)
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(const _PassphraseResult('', remove: true)),
              child: Text(context.t.dataBackup.passphraseRemove),
            ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          DesignTokens.spacingSm,
          DesignTokens.spacingMd,
          DesignTokens.spacingMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passphrase,
              focusNode: passphraseFocus,
              autofocus: true,
              obscureText: !showPassphrase.value,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: _confirm
                  ? TextInputAction.next
                  : TextInputAction.done,
              decoration:
                  flatFieldDecoration(
                    context,
                    label: context.t.dataBackup.passphrase,
                  ).copyWith(
                    helperText: context.t.dataBackup.passphraseHint(
                      n: _minLength,
                    ),
                    errorText: error.value?.onConfirmation ?? false
                        ? null
                        : error.value?.message,
                    suffixIcon: IconButton(
                      tooltip: showPassphrase.value
                          ? context.t.hidePassword
                          : context.t.showPassword,
                      icon: Icon(
                        showPassphrase.value
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        showPassphrase.value = !showPassphrase.value;
                      },
                    ),
                  ),
              onSubmitted: _confirm ? null : (_) => submit(),
            ),
            if (_confirm) ...[
              const SizedBox(height: DesignTokens.spacingSm),
              TextField(
                controller: confirmation,
                focusNode: confirmationFocus,
                obscureText: !showPassphrase.value,
                autocorrect: false,
                enableSuggestions: false,
                decoration:
                    flatFieldDecoration(
                      context,
                      label: context.t.dataBackup.passphraseConfirm,
                    ).copyWith(
                      errorText: error.value?.onConfirmation ?? false
                          ? error.value?.message
                          : null,
                    ),
                onSubmitted: (_) => submit(),
              ),
            ],
            if (mode == _PassphraseMode.backup)
              BlockCheckboxTile(
                // The sheet's padding is the gutter, and the tick keeps the
                // trailing edge like every other toggle in the app.
                value: save.value,
                title: context.t.dataBackup.savePassphrase,
                onChanged: (isChecked) => save.value = isChecked,
              ),
          ],
        ),
      ),
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
      trailing: const Icon(Icons.chevron_right),
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

class _MaxBackupSlider extends StatelessWidget {
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
    return SettingsSliderTile(
      title: context.t.periodicBackup.maxBackups,
      value: state.maxBackupCount.toDouble(),
      // The bounds come from the state, which clamps a stored count back into
      // them — a slider that offered more would be offering an assert. There is
      // no draft here either: the row shows what is stored, and the number
      // under the finger is the slider's own business.
      min: PeriodicBackupSettingState.minBackupCount.toDouble(),
      max: PeriodicBackupSettingState.maxBackupCount.toDouble(),
      divisions:
          PeriodicBackupSettingState.maxBackupCount -
          PeriodicBackupSettingState.minBackupCount,
      labelFor: (value) => '${value.round()}',
      enabled: enabled,
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
        // The dots say "a value is here" without leaking it; a reader hears the
        // fact rather than eight bullet characters.
        Text(
          hasPassphrase ? _kSecretMask : context.t.dataBackup.passphraseNotSet,
          semanticsLabel: hasPassphrase
              ? context.t.dataBackup.passphraseSaved
              : null,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final result = await showSheet<_PassphraseResult>(
          context: context,
          builder: (_) => _PassphraseSheet(
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
    final chatId = state.telegramChatId;

    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.telegram.chatId),
      subtitle: RowSubtitle(
        // A bare number in a subtitle leaves a reader guessing which field it
        // belongs to, so the label rides along in the announcement.
        Text(
          chatId.isEmpty ? context.t.periodicBackup.telegram.notSet : chatId,
          semanticsLabel: chatId.isEmpty
              ? null
              : context.t.periodicBackup.telegram.chatIdValue(value: chatId),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
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
    final token = state.telegramBotToken;
    // Only the tail stays visible: enough to tell two saved tokens apart, not
    // enough to read one over a shoulder.
    final tail = token.length <= _kSecretTail
        ? token
        : token.substring(token.length - _kSecretTail);

    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.telegram.botToken),
      subtitle: RowSubtitle(
        // The dots carry the masking on screen and a reader hears only the
        // fact: the tail is for eyes, never for the announcement, so the token
        // does not reach whoever is standing next to the phone.
        Text(
          token.isEmpty
              ? context.t.periodicBackup.telegram.notSet
              : '$_kSecretMask$tail',
          semanticsLabel: token.isEmpty
              ? null
              : context.t.periodicBackup.telegram.botTokenSaved,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: enabled
          ? () async {
              final result = await showTextSheet(
                context: context,
                title: context.t.periodicBackup.telegram.botToken,
                hint: context.t.periodicBackup.telegram.botTokenHint,
                initialValue: state.telegramBotToken,
                saveLabel: context.t.save,
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
          ? Semantics(
              label: context.t.periodicBackup.telegram.connecting,
              child: const SizedBox.square(
                dimension: DesignTokens.iconAction,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
      onTap: !enabled || isLoading.value
          ? null
          : () async {
              isLoading.value = true;
              TelegramResult result;
              try {
                result = await ref
                    .read(telegramBackupServiceProvider.notifier)
                    .testConnection();
              } on Object catch (e, stack) {
                // A throw is a finished attempt too: the row has to say so,
                // or the tap looks like nothing ever happened.
                mainLog.e('Telegram backup: connection test failed', e, stack);
                result = TelegramResult.unknownError;
              } finally {
                // The spinner is the only feedback while this runs, so it has
                // to clear even when the request throws. Only while the row is
                // still on screen: the hook disposed its notifier on a pop.
                if (context.mounted) isLoading.value = false;
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

              showToast(context, message);
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
    // Encryption is a promise the upload cannot quietly break: with nothing
    // stored to seal with, the only archive it could send is the plain one.
    final cannotSeal =
        settings.encryptBackup && settings.backupPassphrase.isEmpty;
    // Read before the first gap: the strings come from an inherited lookup,
    // and the run outlives the row that started it.
    final sent = context.t.periodicBackup.telegram.backupSent;
    final failed = context.t.periodicBackup.telegram.backupFailed;

    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.telegram.backupNow),
      subtitle: RowSubtitle(
        Text(
          // The row is dead until both halves of the address exist, so the
          // line under it names what is missing instead of going quiet.
          !isConfigured
              ? context.t.periodicBackup.telegram.needsChatAndToken
              : cannotSeal
              ? context.t.periodicBackup.telegram.backupNeedsPassphrase
              : context.t.periodicBackup.telegram.backupNowDesc,
        ),
      ),
      trailing: isLoading.value
          ? Semantics(
              label: context.t.periodicBackup.telegram.uploading,
              child: const SizedBox.square(
                dimension: DesignTokens.iconAction,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
      onTap: !enabled || !isConfigured || cannotSeal || isLoading.value
          ? null
          : () async {
              isLoading.value = true;
              String message;
              try {
                final backupFile = await ref
                    .read(dataBackupStateProvider.notifier)
                    .createBackupForTelegram();
                if (backupFile == null) {
                  // Refused: a run is already in flight, or the archive could
                  // not be written. Nothing left the device.
                  message = failed;
                } else {
                  final result = await ref
                      .read(telegramBackupServiceProvider.notifier)
                      .sendBackupFile(backupFile);
                  if (result == TelegramResult.success) {
                    await ref
                        .read(periodicBackupSettingStateProvider.notifier)
                        .setLastBackupTime(DateTime.now());
                  }
                  message = result == TelegramResult.success ? sent : failed;
                }
              } on Object catch (e, stack) {
                // The archive is written before the upload starts, so a throw
                // here can mean either half failed. Either way the row has to
                // say so instead of going back to idle in silence.
                mainLog.e('Telegram backup: backup now failed', e, stack);
                message = failed;
              } finally {
                // The spinner is the only feedback while this runs, so it has
                // to clear even when the backup throws — and only while the
                // row is still on screen: its notifier is gone after a pop.
                if (context.mounted) isLoading.value = false;
              }

              if (!context.mounted) return;
              showToast(context, message);
            },
    );
  }
}
