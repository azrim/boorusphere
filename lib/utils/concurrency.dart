/// Runs [action] for every item with at most [limit] calls in flight.
///
/// A batch can carry a large selection of URLs; running them all at once
/// would open one connection per file and hold every response in memory
/// together. Results keep the order of [items] regardless of which call
/// settles first. A failing call does not cancel the calls already running;
/// the first error is rethrown once every worker has settled.
Future<List<R>> mapConcurrent<T, R>(
  Iterable<T> items, {
  required int limit,
  required Future<R> Function(T item, int index) action,
}) async {
  final list = items.toList(growable: false);
  if (list.isEmpty) return <R>[];

  final results = List<R?>.filled(list.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      // Read and bump with no await in between: two workers can never take
      // the same index.
      final index = next;
      if (index >= list.length) return;
      next = index + 1;
      results[index] = await action(list[index], index);
    }
  }

  final workers = limit < 1 ? 1 : (limit > list.length ? list.length : limit);
  await Future.wait([
    for (var i = 0; i < workers; i++) worker(),
  ], eagerError: false);

  return results.cast<R>();
}
