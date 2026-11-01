import 'dart:collection';

import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tag_info_cache.g.dart';

/// Small LRU of tag descriptions, keyed by `(serverId, tag)`.
///
/// A sheet is opened again and again for the same handful of tags while
/// browsing, and a tag description changes slowly. The cache keeps the last
/// answers so a revisit is instant and costs no request. Failures are never
/// stored: a server that was briefly unreachable must be asked again on the
/// next open, not answered with the same error from memory.
class TagInfoCache {
  TagInfoCache({
    this.maxEntries = 100,
    this.ttl = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Upper bound on remembered tags; entries beyond it are the least recently
  /// used ones.
  final int maxEntries;

  /// How long an answer stays usable. Post counts and wikis move slowly, so a
  /// quarter of an hour is a freshness compromise rather than a correctness
  /// limit.
  final Duration ttl;

  final DateTime Function() _clock;
  final LinkedHashMap<String, _CacheEntry> _entries = LinkedHashMap();

  /// The answer cached for [tag] on [serverId], or null on a miss or after
  /// [ttl].
  TagInfo? get(String serverId, String tag) {
    final key = _keyOf(serverId, tag);
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_clock().difference(entry.storedAt) > ttl) return null;

    // Reinserting moves the tag to the most-recently-used end.
    _entries[key] = entry;
    return entry.info;
  }

  void put(String serverId, String tag, TagInfo info) {
    final key = _keyOf(serverId, tag);
    _entries.remove(key);
    _entries[key] = _CacheEntry(info, _clock());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Forgets one answer, so an explicit retry goes back to the wire instead of
  /// replaying the answer the reader just asked to refresh.
  void remove(String serverId, String tag) {
    _entries.remove(_keyOf(serverId, tag));
  }

  void clear() => _entries.clear();

  /// Tag names are case-insensitive, the way the engines answer them; the
  /// server keeps its own scope so the same word on two boorus never collides.
  static String _keyOf(String serverId, String tag) =>
      '$serverId\u0000${tag.trim().toLowerCase()}';
}

class _CacheEntry {
  const _CacheEntry(this.info, this.storedAt);

  final TagInfo info;
  final DateTime storedAt;
}

@Riverpod(keepAlive: true)
TagInfoCache tagInfoCache(Ref ref) => TagInfoCache();
