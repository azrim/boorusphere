import 'dart:collection';

import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'suggestion_cache.g.dart';

/// Small LRU of answered tag suggestions, keyed by `(serverId, word)`.
///
/// Suggestions are asked for on every pause while typing, and the same prefix
/// is retyped constantly (backspace, reopen the bar, switch between two tags).
/// Keeping the last answers avoids those round-trips without caching a failure:
/// [put] is only called with a non-empty successful answer.
///
/// The cache is scoped to one server at a time. A tag means different things
/// on different boorus, so switching servers drops the previous scope instead
/// of letting its answers leak into the new one.
class SuggestionCache {
  SuggestionCache({
    this.maxEntries = 150,
    this.ttl = const Duration(minutes: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Upper bound on remembered words; entries beyond it are the least recently
  /// used ones.
  final int maxEntries;

  /// How long an answer stays usable. Booru post counts move slowly, so half an
  /// hour is a freshness compromise rather than a correctness limit.
  final Duration ttl;

  final DateTime Function() _clock;
  final LinkedHashMap<String, _CacheEntry> _entries = LinkedHashMap();

  /// Server the current entries belong to; null before the first ask.
  String? _server;

  /// Answer cached for [word] on [serverId], or null on a miss or after [ttl].
  List<Suggestion>? get(String serverId, String word) {
    _scopeTo(serverId);

    final key = _keyOf(word);
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_clock().difference(entry.storedAt) > ttl) return null;

    // Reinserting moves the word to the most-recently-used end.
    _entries[key] = entry;
    return entry.suggestions;
  }

  /// Remembers [suggestions] for [word]. An empty answer is not stored, so a
  /// later keystroke can ask the server again instead of replaying the miss.
  void put(String serverId, String word, List<Suggestion> suggestions) {
    if (suggestions.isEmpty) return;
    _scopeTo(serverId);

    final key = _keyOf(word);
    _entries.remove(key);
    _entries[key] = _CacheEntry(suggestions, _clock());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() {
    _entries.clear();
    _server = null;
  }

  /// Drops everything when the reader has moved to another server.
  void _scopeTo(String serverId) {
    if (_server == serverId) return;
    _entries.clear();
    _server = serverId;
  }

  /// Word matching is case-insensitive, the way the engines answer it.
  static String _keyOf(String word) => word.toLowerCase();
}

class _CacheEntry {
  const _CacheEntry(this.suggestions, this.storedAt);

  final List<Suggestion> suggestions;
  final DateTime storedAt;
}

@Riverpod(keepAlive: true)
SuggestionCache suggestionCache(Ref ref) => SuggestionCache();
