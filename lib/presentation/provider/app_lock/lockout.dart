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

/// When the next PIN may be tried, or null while attempts are still free.
///
/// The wait grows with the number of wrong attempts, so a mistyped PIN costs a
/// moment while a run of guesses costs minutes.
DateTime? pinRetryAt(int failedAttempts, DateTime now) {
  if (failedAttempts <= freePinAttempts) return null;

  final wait = failedAttempts < 8 ? shortPinLockout : longPinLockout;
  return now.add(wait);
}
