import 'package:boorusphere/presentation/provider/booru/suggestion_cache.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:flutter_test/flutter_test.dart';

Suggestion _suggestion(String name) => Suggestion(name, 1);

void main() {
  test('a word is answered from the cache until its entry expires', () {
    var now = DateTime(2026, 1, 1);
    final cache = SuggestionCache(
      maxEntries: 10,
      ttl: const Duration(minutes: 30),
      clock: () => now,
    );
    cache.put('S', 'book', [_suggestion('book')]);

    expect(cache.get('S', 'book'), hasLength(1));

    now = now.add(const Duration(minutes: 31));
    expect(cache.get('S', 'book'), isNull);
  });

  test('the least recently used word is dropped first', () {
    final cache = SuggestionCache(maxEntries: 2);
    cache.put('S', 'a', [_suggestion('a')]);
    cache.put('S', 'b', [_suggestion('b')]);

    // Reading `a` makes `b` the least recently used entry.
    expect(cache.get('S', 'a'), isNotNull);
    cache.put('S', 'c', [_suggestion('c')]);

    expect(cache.get('S', 'b'), isNull);
    expect(cache.get('S', 'a'), isNotNull);
    expect(cache.get('S', 'c'), isNotNull);
  });

  test('another server never reads the previous server cache', () {
    final cache = SuggestionCache();
    cache.put('A', 'book', [_suggestion('book')]);

    expect(cache.get('B', 'book'), isNull);

    cache.put('B', 'book', [_suggestion('book')]);
    // Switching servers drops the old scope instead of mixing the two.
    expect(cache.get('A', 'book'), isNull);
  });

  test('an empty answer is not stored', () {
    final cache = SuggestionCache();
    cache.put('S', 'book', const []);

    expect(cache.get('S', 'book'), isNull);
  });
}
