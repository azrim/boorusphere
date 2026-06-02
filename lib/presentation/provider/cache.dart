import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cache.g.dart';

/// Custom cache configuration with LRU eviction:
/// - maxNrOfCacheObjects: 500 (limits cache to 500 items)
/// - stalePeriod: 7 days (auto-cleanup of unused items)
const _cacheKey = 'boorusphere_cache';
const _maxCacheObjects = 500;
const _stalePeriod = Duration(days: 7);

/// Custom CacheManager with configured settings for LRU eviction.
class BooruCacheManager extends CacheManager {
  BooruCacheManager._()
    : super(
        Config(
          _cacheKey,
          stalePeriod: _stalePeriod,
          maxNrOfCacheObjects: _maxCacheObjects,
        ),
      );

  static final BooruCacheManager _instance = BooruCacheManager._();

  static BooruCacheManager get instance => _instance;
}

@Riverpod(keepAlive: true)
CacheManager cacheManager(Ref ref) {
  // Use custom cache manager with LRU eviction and sensible defaults.
  // When maxNrOfCacheObjects is reached, least recently used items
  // are automatically evicted.
  return BooruCacheManager.instance;
}
