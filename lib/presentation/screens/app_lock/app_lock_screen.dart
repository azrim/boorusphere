import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_lock/app_lock_state.dart';
import 'package:boorusphere/presentation/provider/app_lock/clock.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/pin_field.dart';
import 'package:boorusphere/presentation/widgets/pin_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The gate keeps one reading measure on a wide screen: the mark, the title and
/// the pad stay a column instead of stretching edge to edge.
const double _kGateMaxWidth = 360.0;

/// The emblem behind the lock glyph: a filled circle a step over the row chip,
/// with the glyph at half its width so it reads as a mark rather than a button.
const double _kGateMarkSize = 56.0;
const double _kGateMarkGlyph = 28.0;

/// Digits a PIN may run long; the dots row shows this many slots.
const int _kPinLength = 8;

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
    final pin = useState('');
    final error = useState<String?>(null);
    final busy = useState(false);

    Future<void> useBiometrics({bool auto = false}) async {
      if (busy.value) return;
      if (auto && throttled) return;
      error.value = null;
      busy.value = true;
      final result = await ref
          .read(appLockProvider.notifier)
          .unlockWithBiometrics(t.appLock.biometricPrompt);
      if (!context.mounted) return;
      busy.value = false;

      error.value = switch (result) {
        UnlockResult.biometricLockout => t.appLock.biometricLockedOut,
        UnlockResult.failed => auto ? null : t.appLock.biometricFailed,
        UnlockResult.unavailable => t.appLock.biometricUnavailable,
        UnlockResult.canceled ||
        UnlockResult.success ||
        UnlockResult.wrongPin ||
        UnlockResult.throttled ||
        UnlockResult.busy => null,
      };
    }

    // The biometric prompt answers once per appearance of the gate: a cancel
    // or a miss leaves the choice to the user, and the button below still
    // opens the prompt by hand.
    final biometricsOffered = useState(false);
    useEffect(() {
      if (!biometricsOffered.value &&
          lock.biometricsAvailable &&
          !throttled &&
          !busy.value) {
        biometricsOffered.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          useBiometrics(auto: true);
        });
      }
      return null;
    }, [lock.biometricsAvailable, throttled]);

    Future<void> submit() async {
      if (busy.value || throttled) return;
      if (pin.value.isEmpty) return;

      error.value = null;
      busy.value = true;
      final result = await ref
          .read(appLockProvider.notifier)
          .unlockWithPin(pin.value);
      if (!context.mounted) return;
      busy.value = false;

      switch (result) {
        case UnlockResult.success:
          break;
        case UnlockResult.wrongPin:
          error.value = t.appLock.wrongPin;
          pin.value = '';
        case UnlockResult.throttled:
          // The live countdown replaces the message.
          error.value = null;
          pin.value = '';
        case UnlockResult.unavailable:
          error.value = t.appLock.unavailable;
        case UnlockResult.canceled:
        case UnlockResult.biometricLockout:
        case UnlockResult.failed:
        case UnlockResult.busy:
          break;
      }
    }

    void appendDigit(String digit) {
      if (busy.value || throttled) return;
      if (pin.value.length >= _kPinLength) return;
      error.value = null;
      pin.value = pin.value + digit;
      if (pin.value.length == _kPinLength) submit();
    }

    void backspace() {
      if (pin.value.isEmpty) return;
      pin.value = pin.value.substring(0, pin.value.length - 1);
    }

    final scheme = context.colorScheme;
    final textTheme = context.theme.textTheme;

    // A bare surface, not a Scaffold: this cover sits above the navigator, so
    // a Scaffold here would register with the app's messenger as a second root
    // and have nothing to host (no app bar, no snackbar, no FAB).
    return Material(
      color: context.theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
            vertical: DesignTokens.spacingMd,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.sizeOf(context).height -
                  MediaQuery.paddingOf(context).vertical -
                  DesignTokens.spacingMd * 2,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kGateMaxWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: _kGateMarkSize,
                        height: _kGateMarkSize,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: _kGateMarkGlyph,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacingLg),
                    // A gate is a hero, not a row: the title takes the
                    // display step the theme already reserves for a
                    // full-screen gate. The line under it is a supporting
                    // line like every other title, so it takes that role
                    // rather than a size of its own.
                    Text(
                      t.appLock.lockedTitle,
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall,
                    ),
                    const SizedBox(height: DesignTokens.spacingSm),
                    Text(
                      t.appLock.lockedDesc,
                      textAlign: TextAlign.center,
                      style: AppTextRoles.of(context).rowSupporting,
                    ),
                    const SizedBox(height: DesignTokens.spacingXl),
                    PinDots(
                      length: pin.value.length,
                      maxLength: _kPinLength,
                      error: error.value != null,
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
                    PinKeypad(
                      onDigit: appendDigit,
                      onBackspace: backspace,
                      enabled: !busy.value && !throttled,
                    ),
                    if (lock.biometricsAvailable) ...[
                      const SizedBox(height: DesignTokens.spacingLg),
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
        ),
      ),
    );
  }
}
