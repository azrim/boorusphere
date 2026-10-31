/// Wrong PINs allowed before a wait begins.
const int freePinAttempts = 4;

/// Wait after the fifth to seventh wrong PIN.
const Duration shortPinLockout = Duration(seconds: 30);

/// Wait from the eighth wrong PIN on.
const Duration longPinLockout = Duration(minutes: 5);

/// When the next PIN may be tried, or null while attempts are still free.
///
/// The wait grows with the number of wrong attempts, so a mistyped PIN costs a
/// moment while a run of guesses costs minutes.
DateTime? pinRetryAt(int failedAttempts, DateTime now) {
  if (failedAttempts <= freePinAttempts) return null;

  final wait = failedAttempts < 8 ? shortPinLockout : longPinLockout;
  return now.add(wait);
}
