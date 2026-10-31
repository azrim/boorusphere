import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/domain/repository/app_lock_repo.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_lock/app_lock_state.dart';
import 'package:boorusphere/presentation/provider/app_lock/clock.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/screens/settings/widgets/settings_section.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/pin_field.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:boorusphere/presentation/widgets/settings_sheet.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class AppLockPage extends ConsumerWidget {
  const AppLockPage({super.key});

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final t = context.t;
    try {
      if (enabled) {
        final pin = await showPinSetupSheet(
          context,
          title: t.appLock.setupTitle,
          description: t.appLock.setupDesc,
        );
        if (pin == null || !context.mounted) return;

        await ref.read(appLockProvider.notifier).enable(pin);
        if (context.mounted) showToast(context, t.appLock.saved);
      } else {
        final verified = await showPinVerifySheet(
          context,
          title: t.appLock.verifyTitle,
          description: t.appLock.verifyDesc,
        );
        if (verified != true || !context.mounted) return;

        await ref.read(appLockProvider.notifier).disable();
        if (context.mounted) showToast(context, t.appLock.removed);
      }
    } on AppLockUnavailableException {
      if (context.mounted) showToast(context, t.appLock.unavailable);
    }
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final t = context.t;
    try {
      final verified = await showPinVerifySheet(
        context,
        title: t.appLock.verifyTitle,
        description: t.appLock.verifyDesc,
      );
      if (verified != true || !context.mounted) return;

      final pin = await showPinSetupSheet(
        context,
        title: t.appLock.changePin,
        description: t.appLock.setupDesc,
      );
      if (pin == null || !context.mounted) return;

      await ref.read(appLockProvider.notifier).changePin(pin);
      if (context.mounted) showToast(context, t.appLock.changed);
    } on AppLockUnavailableException {
      if (context.mounted) showToast(context, t.appLock.unavailable);
    }
  }

  Future<void> _pickTimeout(
    BuildContext context,
    WidgetRef ref,
    LockTimeout selected,
  ) async {
    final t = context.t;
    final picked = await showChoiceSheet<LockTimeout>(
      context: context,
      title: t.appLock.timeoutTitle,
      selected: selected,
      choices: [
        for (final timeout in LockTimeout.values)
          Choice(value: timeout, label: _timeoutLabel(context, timeout)),
      ],
    );
    if (picked == null || !context.mounted) return;

    try {
      await ref.read(appLockProvider.notifier).setTimeout(picked.value);
    } on AppLockUnavailableException {
      if (context.mounted) showToast(context, t.appLock.unavailable);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final lock = ref.watch(appLockProvider);
    final flagSecure = ref.watch(
      uiSettingStateProvider.select((ui) => ui.flagSecure),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t.appLock.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
          ),
          children: [
            SettingsSection(
              title: t.settings.privacy,
              children: [
                SwitchListTile(
                  title: Text(t.appLock.title),
                  subtitle: RowSubtitle(
                    Text(
                      lock.isActive
                          ? _timeoutLabel(context, lock.timeout)
                          : t.appLock.desc,
                    ),
                  ),
                  value: lock.isActive,
                  onChanged: (value) => _setEnabled(context, ref, value),
                ),
                if (lock.isActive) ...[
                  ListTile(
                    title: Text(t.appLock.timeoutTitle),
                    subtitle: RowSubtitle(
                      Text(_timeoutLabel(context, lock.timeout)),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickTimeout(context, ref, lock.timeout),
                  ),
                  ListTile(
                    title: Text(t.appLock.changePin),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _changePin(context, ref),
                  ),
                ],
                SwitchListTile(
                  title: Text(t.appLock.screenshotTitle),
                  subtitle: RowSubtitle(Text(t.appLock.screenshotDesc)),
                  value: flagSecure,
                  onChanged: (value) async {
                    await ref
                        .read(uiSettingStateProvider.notifier)
                        .setFlagSecure(value);
                    if (!value && context.mounted) {
                      showToast(context, t.appLock.screenshotOffWarning);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingLg),
            NoticeCard(
              icon: const Icon(Icons.info_outline_rounded),
              children: Column(
                children: [
                  Text(
                    t.appLock.forgotTitle,
                    textAlign: TextAlign.center,
                    style: context.theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: DesignTokens.spacingXs),
                  Text(
                    t.appLock.forgotDesc,
                    textAlign: TextAlign.center,
                    style: AppTextRoles.of(context).rowSupporting,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeoutLabel(BuildContext context, LockTimeout timeout) {
  return switch (timeout) {
    LockTimeout.immediate => context.t.appLock.timeoutImmediate,
    LockTimeout.seconds30 => context.t.appLock.timeout30Seconds,
    LockTimeout.minutes1 => context.t.appLock.timeout1Minute,
    LockTimeout.minutes5 => context.t.appLock.timeout5Minutes,
    LockTimeout.never => context.t.appLock.timeoutNever,
  };
}

/// Asks for a new PIN twice, so a typo does not become the only way in.
Future<String?> showPinSetupSheet(
  BuildContext context, {
  required String title,
  String? description,
}) {
  return showSheet<String>(
    context: context,
    builder: (context) =>
        _PinSetupSheet(title: title, description: description),
  );
}

class _PinSetupSheet extends HookWidget {
  const _PinSetupSheet({required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final pinController = useTextEditingController();
    final confirmController = useTextEditingController();
    final pinError = useState<String?>(null);
    final confirmError = useState<String?>(null);

    void save() {
      final pin = pinController.text;
      if (pin.length < 4) {
        pinError.value = t.appLock.pinTooShort;
        confirmError.value = null;
        return;
      }
      if (pin != confirmController.text) {
        pinError.value = null;
        confirmError.value = t.appLock.pinMismatch;
        return;
      }
      Navigator.pop(context, pin);
    }

    final description = this.description;

    return SheetShell(
      title: title,
      maxHeightFactor: 0.62,
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: save, child: Text(t.save)),
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
          children: [
            if (description != null) ...[
              Text(description, style: AppTextRoles.of(context).rowSupporting),
              const SizedBox(height: DesignTokens.spacingMd),
            ],
            PinField(
              controller: pinController,
              label: t.appLock.newPin,
              hint: t.appLock.pinHint,
              autofocus: true,
              errorText: pinError.value,
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            PinField(
              controller: confirmController,
              label: t.appLock.confirmPin,
              errorText: confirmError.value,
              onSubmitted: (_) => save(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirms the current PIN or a biometric, then answers true.
Future<bool?> showPinVerifySheet(
  BuildContext context, {
  required String title,
  String? description,
}) {
  return showSheet<bool>(
    context: context,
    builder: (context) =>
        _PinVerifySheet(title: title, description: description),
  );
}

class _PinVerifySheet extends HookConsumerWidget {
  const _PinVerifySheet({required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final lock = ref.watch(appLockProvider);
    final throttled = lock.isThrottledAt(ref.watch(clockProvider).now());
    final retryAt = lock.retryAt;
    final controller = useTextEditingController();
    final error = useState<String?>(null);
    final busy = useState(false);

    Future<void> submit() async {
      if (busy.value || throttled) return;
      final pin = controller.text;
      if (pin.isEmpty) return;

      error.value = null;
      busy.value = true;
      final result = await ref.read(appLockProvider.notifier).checkPin(pin);
      if (!context.mounted) return;
      busy.value = false;

      switch (result) {
        case UnlockResult.success:
          Navigator.pop(context, true);
        case UnlockResult.wrongPin:
          error.value = t.appLock.wrongPin;
          controller.clear();
        case UnlockResult.throttled:
          error.value = null;
          controller.clear();
        case UnlockResult.unavailable:
          error.value = t.appLock.unavailable;
        case UnlockResult.canceled:
        case UnlockResult.biometricLockout:
        case UnlockResult.failed:
        case UnlockResult.busy:
          break;
      }
    }

    Future<void> useBiometrics() async {
      if (busy.value) return;
      error.value = null;
      busy.value = true;
      final result = await ref
          .read(appLockProvider.notifier)
          .unlockWithBiometrics(t.appLock.biometricPrompt);
      if (!context.mounted) return;
      busy.value = false;

      switch (result) {
        case UnlockResult.success:
          Navigator.pop(context, true);
        case UnlockResult.biometricLockout:
          error.value = t.appLock.biometricLockedOut;
        case UnlockResult.failed:
          error.value = t.appLock.biometricFailed;
        case UnlockResult.unavailable:
          error.value = t.appLock.biometricUnavailable;
        case UnlockResult.canceled:
        case UnlockResult.wrongPin:
        case UnlockResult.throttled:
        case UnlockResult.busy:
          break;
      }
    }

    final description = this.description;
    final scheme = context.colorScheme;
    final textTheme = context.theme.textTheme;

    return SheetShell(
      title: title,
      maxHeightFactor: 0.62,
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy.value || throttled ? null : submit,
          child: Text(
            busy.value ? t.appLock.unlocking : t.appLock.confirmAction,
          ),
        ),
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
          children: [
            if (description != null) ...[
              Text(description, style: AppTextRoles.of(context).rowSupporting),
              const SizedBox(height: DesignTokens.spacingMd),
            ],
            PinField(
              controller: controller,
              label: t.appLock.pin,
              autofocus: true,
              enabled: !busy.value && !throttled,
              onSubmitted: (_) => submit(),
            ),
            if (throttled && retryAt != null) ...[
              pinMessageGap,
              PinRetryCountdown(
                retryAt: retryAt,
                secondsLabel: (seconds) => t.appLock.retryIn(seconds: seconds),
              ),
            ] else if (error.value case final message?) ...[
              pinMessageGap,
              Text(
                message,
                style: textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            if (lock.biometricsAvailable) ...[
              const SizedBox(height: DesignTokens.spacingSm),
              TextButton.icon(
                onPressed: busy.value ? null : useBiometrics,
                icon: const Icon(
                  Icons.fingerprint_rounded,
                  size: DesignTokens.iconAction,
                ),
                label: Text(t.appLock.biometric),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
