/// Wrong PINs allowed before a wait begins.
const int freePinAttempts = 4;

/// Wait after the fifth to seventh wrong PIN.
const Duration shortPinLockout = Duration(seconds: 30);

/// Wait from the eighth wrong PIN on.
const Duration longPinLockout = Duration(minutes: 5);

/// How long a system surface the app opened itself may cover it before the
/// trip counts as leaving the app.
///
/// The file picker pauses the app like any other activity, but the user is
/// still in the flow they started. A quick round-trip keeps the session; a
/// longer one locks on return like any other departure.
const Duration externalFlowCeiling = Duration(seconds: 60);

/// How long the app may stay in the background with the biometric prompt
/// open before the trip counts as leaving it.
///
/// The prompt pauses the app like any other activity, and the plugin keeps
/// the sheet across that pause instead of canceling it. A quick switch away
/// and back is still the unlock the user started; a longer absence means
/// they walked away from an open prompt, so the session locks on return
/// like any other departure. Shorter than the picker ceiling on purpose:
/// an abandoned security gate is not a flow the app opened for the user.
const Duration authFlowCeiling = Duration(seconds: 10);

/// When the next PIN may be tried, or null while attempts are still free.
///
/// The wait grows with the number of wrong attempts, so a mistyped PIN costs a
/// moment while a run of guesses costs minutes.
DateTime? pinRetryAt(int failedAttempts, DateTime now) {
  if (failedAttempts <= freePinAttempts) return null;

  final wait = failedAttempts < 8 ? shortPinLockout : longPinLockout;
  return now.add(wait);
}
