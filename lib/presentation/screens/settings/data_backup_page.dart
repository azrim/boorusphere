import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_option.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_result.dart';
import 'package:boorusphere/presentation/provider/data_backup/telegram_backup_service.dart';
import 'package:boorusphere/presentation/provider/settings/periodic_backup_state.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
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
    final periodicNotifier =
        ref.read(periodicBackupSettingStateProvider.notifier);

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
          context.scaffoldMessenger.showSnackBar(SnackBar(
            content: Text(context.t.dataBackup.restore.success),
            duration: const Duration(seconds: 2),
          ));
          Future.delayed(const Duration(seconds: 2), SystemNavigator.pop);
        case ExportedBackupResult(:final path):
          context.scaffoldMessenger.showSnackBar(SnackBar(
            content: Text(context.t.dataBackup.backup.success(dest: path)),
            duration: const Duration(seconds: 2),
          ));
        case ErrorBackupResult():
          context.scaffoldMessenger.showSnackBar(SnackBar(
            content: Text(context.t.dataBackup.restore.invalid),
            duration: const Duration(seconds: 1),
          ));
        default:
      }
    });

    return ListView(
      children: [
        // Manual Backup Section
        _SectionHeader(title: context.t.dataBackup.backup.title),
        ListTile(
          leading: const Icon(Icons.backup),
          title: Text(context.t.dataBackup.backup.title),
          subtitle: Text(context.t.dataBackup.backup.desc),
          onTap: () async {
            final result = await showDialog<BackupOption?>(
              context: context,
              builder: (context) => _BackupSelectionDialog(),
            );
            if (result != null) {
              unawaited(ref
                  .read(dataBackupStateProvider.notifier)
                  .backup(option: result));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: Text(context.t.dataBackup.restore.title),
          subtitle: Text(context.t.dataBackup.restore.desc),
          onTap: () {
            ref
                .read(dataBackupStateProvider.notifier)
                .restore(onConfirm: () => _warningDialog(context));
          },
        ),
        const Divider(height: 32),

        // Periodic Backup Section
        _SectionHeader(title: context.t.periodicBackup.title),
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
          subtitle: Text(context.t.periodicBackup.deleteOldDesc),
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
        const Divider(height: 32),

        // Telegram Section
        _SectionHeader(title: context.t.periodicBackup.telegram.title),
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
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
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
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
          Text(
            type == DataBackupType.backup
                ? context.t.dataBackup.backup.loading
                : context.t.dataBackup.restore.loading,
          ),
        ],
      ),
    );
  }
}

class _BackupSelectionDialog extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final option = useState(const BackupOption());
    return AlertDialog(
      title: Text(context.t.dataBackup.backup.title),
      icon: const Icon(Icons.backup),
      content: Column(
        mainAxisSize: MainAxisSize.min,
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
      actions: [
        TextButton(
          onPressed: () => context.navigator.pop(),
          child: Text(context.t.cancel),
        ),
        ElevatedButton(
          onPressed: option.value.isValid()
              ? () => context.navigator.pop(option.value)
              : null,
          child: Text(context.t.backup),
        ),
      ],
    );
  }
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
      subtitle: Text(state.frequency.label),
      onTap: enabled
          ? () async {
              final result = await showDialog<BackupFrequency>(
                context: context,
                builder: (dialogContext) => SimpleDialog(
                  title: Text(context.t.periodicBackup.frequency),
                  children: BackupFrequency.values.map((freq) {
                    return RadioGroup<BackupFrequency>(
                      groupValue: state.frequency,
                      onChanged: (value) => Navigator.pop(dialogContext, value),
                      child: ListTile(
                        leading: Radio<BackupFrequency>(value: freq),
                        title: Text(freq.label),
                        onTap: () => Navigator.pop(dialogContext, freq),
                      ),
                    );
                  }).toList(),
                ),
              );
              if (result != null) {
                await notifier.setFrequency(result);
              }
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

    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.maxBackups),
      subtitle: Slider(
        value: sliderValue.value,
        min: 1,
        max: 10,
        divisions: 9,
        label: sliderValue.value.round().toString(),
        onChanged: enabled ? (value) => sliderValue.value = value : null,
        onChangeEnd: enabled
            ? (value) => notifier.setMaxBackupCount(value.round())
            : null,
      ),
      trailing: Text('${sliderValue.value.round()}'),
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
      subtitle: Text(_formatLastBackup(context, lastBackupTime)),
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
              final controller =
                  TextEditingController(text: state.telegramChatId);
              final result = await showDialog<String>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(context.t.periodicBackup.telegram.chatId),
                  content: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: context.t.periodicBackup.telegram.chatIdHint,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(context.t.cancel),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, controller.text),
                      child: Text(context.t.save),
                    ),
                  ],
                ),
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
              final controller =
                  TextEditingController(text: state.telegramBotToken);
              final result = await showDialog<String>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(context.t.periodicBackup.telegram.botToken),
                  content: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: context.t.periodicBackup.telegram.botTokenHint,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(context.t.cancel),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, controller.text),
                      child: Text(context.t.save),
                    ),
                  ],
                ),
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
      subtitle: Text(context.t.periodicBackup.telegram.openBotDesc),
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
              final result = await ref
                  .read(telegramBackupServiceProvider.notifier)
                  .testConnection();
              isLoading.value = false;

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
    final isConfigured = settings.telegramChatId.isNotEmpty &&
        settings.telegramBotToken.isNotEmpty;

    return ListTile(
      enabled: enabled,
      title: Text(context.t.periodicBackup.telegram.backupNow),
      subtitle: Text(context.t.periodicBackup.telegram.backupNowDesc),
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

              // Create backup file
              final backupFile = await ref
                  .read(dataBackupStateProvider.notifier)
                  .createBackupForTelegram();

              if (backupFile == null) {
                isLoading.value = false;
                if (context.mounted) {
                  context.scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content:
                          Text(context.t.periodicBackup.telegram.backupFailed),
                    ),
                  );
                }
                return;
              }

              // Send to Telegram
              final result = await ref
                  .read(telegramBackupServiceProvider.notifier)
                  .sendBackupFile(backupFile);

              isLoading.value = false;

              if (!context.mounted) return;

              final message = result == TelegramResult.success
                  ? context.t.periodicBackup.telegram.backupSent
                  : context.t.periodicBackup.telegram.backupFailed;

              context.scaffoldMessenger.showSnackBar(
                SnackBar(content: Text(message)),
              );

              // Update last backup time on success
              if (result == TelegramResult.success) {
                await ref
                    .read(periodicBackupSettingStateProvider.notifier)
                    .setLastBackupTime(DateTime.now());
              }
            },
    );
  }
}
