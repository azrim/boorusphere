import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:mocktail/mocktail.dart';

/// Mocktail stand-in for [CacheManager].
///
/// Lets widget tests drive the video download stream by hand (emit a
/// [FileResponse] or an error on demand) and observe the cache eviction
/// triggered by the manual retry path, without touching the real
/// disk-backed cache or any platform channel.
class MockCacheManager extends Mock implements CacheManager {}
