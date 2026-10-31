import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_lock/app_lock_state.dart';
import 'package:boorusphere/presentation/provider/app_lock/clock.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/pin_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The opaque cover shown over the app while the lock is on.
///
/// It sits above the whole navigator instead of being a route, so unlocking
/// returns to the page that was open rather than to the start screen.
class AppLockScreen extends HookConsumerWidget {
  const AppLockScreen({super.key});

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
      final result = await ref
          .read(appLockProvider.notifier)
          .unlockWithPin(pin);
      if (!context.mounted) return;
      busy.value = false;

      switch (result) {
        case UnlockResult.success:
          break;
        case UnlockResult.wrongPin:
          error.value = t.appLock.wrongPin;
          controller.clear();
        case UnlockResult.throttled:
          // The live countdown replaces the message.
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

      error.value = switch (result) {
        UnlockResult.biometricLockout => t.appLock.biometricLockedOut,
        UnlockResult.failed => t.appLock.biometricFailed,
        UnlockResult.unavailable => t.appLock.biometricUnavailable,
        UnlockResult.canceled ||
        UnlockResult.success ||
        UnlockResult.wrongPin ||
        UnlockResult.throttled ||
        UnlockResult.busy => null,
      };
    }

    final scheme = context.colorScheme;
    final textTheme = context.theme.textTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingLg,
                vertical: DesignTokens.spacingMd,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - DesignTokens.spacingMd * 2,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.lock_outline_rounded,
                              size: 28,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingLg),
                        Text(
                          t.appLock.lockedTitle,
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingSm),
                        Text(
                          t.appLock.lockedDesc,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingXl),
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
                            secondsLabel: (seconds) =>
                                t.appLock.retryIn(seconds: seconds),
                          ),
                        ] else if (error.value case final message?) ...[
                          pinMessageGap,
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: DesignTokens.spacingLg),
                        FilledButton(
                          onPressed: busy.value || throttled ? null : submit,
                          child: Text(
                            busy.value ? t.appLock.unlocking : t.appLock.unlock,
                          ),
                        ),
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
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
