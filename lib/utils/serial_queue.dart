/// Runs async actions one after another, in the order they were asked.
///
/// Dart has no lock, and a single `await` inside a check-then-act is enough
/// for a second caller to pass the same check: both read the state before
/// either has changed it, and the action that was asked *first* is the one that
/// ends up standing. Queuing the pair makes it atomic again — whoever asks
/// first acts first, and the next one reads what the first left behind.
class SerialQueue {
  Future<void> _tail = Future.value();

  /// Runs [action] after every action asked before it, and hands its result
  /// back to the caller.
  ///
  /// A failure reaches the caller that caused it and does not stall the queue:
  /// one rejected write must not leave everything asked after it never running.
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
