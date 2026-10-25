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

  Future<bool?> _warningDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.t.dataBackup.restore.title),
          icon: const Icon(Icons.restore),
          content: Text(context.t.dataBackup.restore.warning),
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
            builder: (_) => UncontrolledProviderScope(
              container: ProviderScope.containerOf(context),
              child: _LoadingDialog(type: type),
            ),
          );
        case ImportedBackupResult():
          context.scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(context.t.dataBackup.restore.success),
              duration: const Duration(seconds: 2),
            ),
          );
          Future.delayed(const Duration(seconds: 2), SystemNavigator.pop);
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
                final result = await showSettingsSheet<BackupOption>(
                  context: context,
                  builder: (context) => const _BackupOptionSheet(),
                );
                if (result != null) {
                  unawaited(
                    ref
                        .read(dataBackupStateProvider.notifier)
                        .backup(option: result),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(context.t.dataBackup.restore.title),
              subtitle: RowSubtitle(Text(context.t.dataBackup.restore.desc)),
              onTap: () {
                ref
                    .read(dataBackupStateProvider.notifier)
                    .restore(onConfirm: () => _warningDialog(context));
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
    return Dialog(
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
    );
  }
}

class _BackupOptionSheet extends HookWidget {
  const _BackupOptionSheet();

  @override
  Widget build(BuildContext context) {
    final option = useState(const BackupOption());
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
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
        children: [
          CheckboxListTile(
            title: Text(context.t.servers.title),
            value: option.value.server,
            onChanged: (v) =>
                option.value = option.value.copyWith(server: v ?? true),
          ),
          CheckboxListTile(
            title: Text(context.t.searchHistory),
            value: option.value.searchHistory,
            onChanged: (v) =>
                option.value = option.value.copyWith(searchHistory: v ?? true),
          ),
          CheckboxListTile(
            title: Text(context.t.tagsBlocker.title),
            value: option.value.blockedTags,
            onChanged: (v) =>
                option.value = option.value.copyWith(blockedTags: v ?? true),
          ),
          CheckboxListTile(
            title: Text(context.t.favorites.title),
            value: option.value.favoritePost,
            onChanged: (v) =>
                option.value = option.value.copyWith(favoritePost: v ?? true),
          ),
          CheckboxListTile(
            title: Text(context.t.settings.title),
            value: option.value.setting,
            onChanged: (v) =>
                option.value = option.value.copyWith(setting: v ?? true),
          ),
        ],
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
