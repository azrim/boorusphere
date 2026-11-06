import 'package:boorusphere/utils/logger.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'biometric_auth.g.dart';

/// The ways a biometric prompt can end without unlocking.
enum BiometricFailure {
  /// The user dismissed the prompt, or the system took it away.
  canceled,

  /// The device stopped accepting biometrics until another unlock method is
  /// used. The PIN is still available for this.
  lockout,

  /// No enrolled biometric, no hardware, or the prompt could not be shown.
  unavailable,

  /// The fingerprint or face was not recognized.
  failed,
}

class BiometricResult {
  const BiometricResult.success() : success = true, failure = null;

  const BiometricResult.failed(BiometricFailure this.failure) : success = false;

  final bool success;
  final BiometricFailure? failure;
}

/// The device biometric prompt, behind an interface so the lock state can be
/// tested without the platform channel.
abstract interface class BiometricAuth {
  Future<bool> isAvailable();

  Future<BiometricResult> authenticate(String reason);

  /// Takes a pending prompt down. The plugin keeps the sheet across a pause
  /// and re-shows it on resume, so a session that locks while the prompt is
  /// open has to cancel it explicitly or the sheet comes back above the
  /// lock cover. Best-effort: a prompt already gone answers anyway.
  Future<void> cancel();
}

class LocalBiometricAuth implements BiometricAuth {
  LocalBiometricAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (e, stack) {
      mainLog.w('App lock: biometric availability is unknown', e, stack);
      return false;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _auth.stopAuthentication();
    } catch (e, stack) {
      mainLog.w(
        'App lock: the biometric prompt could not be canceled',
        e,
        stack,
      );
    }
  }

  @override
  Future<BiometricResult> authenticate(String reason) async {
    try {
      // Biometric only: the PIN is the app's own fallback, so the system sheet
      // must not accept the device PIN and make the two methods overlap.
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return ok
          ? const BiometricResult.success()
          : const BiometricResult.failed(BiometricFailure.failed);
    } on LocalAuthException catch (e) {
      return BiometricResult.failed(switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback =>
          BiometricFailure.canceled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => BiometricFailure.lockout,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          BiometricFailure.unavailable,
        _ => BiometricFailure.failed,
      });
    } on PlatformException catch (e) {
      mainLog.w('App lock: the biometric prompt failed', e);
      return const BiometricResult.failed(BiometricFailure.unavailable);
    } on MissingPluginException catch (e) {
      mainLog.w('App lock: biometrics are not supported here', e);
      return const BiometricResult.failed(BiometricFailure.unavailable);
    }
  }
}

@Riverpod(keepAlive: true)
BiometricAuth biometricAuth(Ref ref) {
  return LocalBiometricAuth();
}
