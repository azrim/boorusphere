import 'dart:io';

import 'package:boorusphere/utils/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The image cache every picture in the app is stored in.
///
/// A plain [CacheManager] cannot resize: `cached_network_image` requires an
/// [ImageCacheManager] for `maxWidthDiskCache`/`maxHeightDiskCache`, and every
/// sized read stores the plain original next to one PNG variant per size. The
/// object cap therefore covers roughly two objects per sized preview, so 500
/// objects keep about 250 previews; 7 days keeps the cache an optimisation
/// rather than an archive.
const _cacheKey = 'boorusphere_cache';
const _maxCacheObjects = 500;
const _stalePeriod = Duration(days: 7);

/// The one image cache in the app.
///
/// [installImageCache] makes it the default of `cached_network_image`, so every
/// image widget — and the viewer's retry, which evicts by URL — reads and
/// writes the same store. The downloader and the settings screen use [instance]
/// directly because they do not go through an image provider.
class BooruCacheManager extends CacheManager with ImageCacheManager {
  BooruCacheManager._()
    : super(
        Config(
          _cacheKey,
          stalePeriod: _stalePeriod,
          maxNrOfCacheObjects: _maxCacheObjects,
        ),
      );

  static final BooruCacheManager instance = BooruCacheManager._();
}

/// Points every network image at [BooruCacheManager].
///
/// Without this the package falls back to its own [DefaultCacheManager], whose
/// 200-object/30-day defaults are not the policy this app declares.
void installImageCache() {
  CachedNetworkImageProvider.defaultCacheManager = BooruCacheManager.instance;
}

/// Removes the image cache older builds stored through the package default.
///
/// Nothing reads it any more; leaving it would keep its files in the cache
/// directory until the system trims it. The legacy manager is emptied instead
/// of deleting the directory so its database rows go with the files.
Future<void> discardLegacyImageCache() async {
  try {
    final root = await getTemporaryDirectory();
    final legacy = Directory(p.join(root.path, DefaultCacheManager.key));
    if (!legacy.existsSync() || legacy.listSync().isEmpty) return;
    await DefaultCacheManager().emptyCache();
    mainLog.i('Cache: removed the legacy image cache');
  } catch (e, stack) {
    mainLog.w('Cache: failed to remove the legacy image cache', e, stack);
  }
}
