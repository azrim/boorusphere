import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cache.g.dart';

@Riverpod(keepAlive: true)
DefaultCacheManager cacheManager(Ref ref) {
  return DefaultCacheManager();
}
