import 'dart:async';

import 'package:boorusphere/presentation/utils/entity/pixel_size.dart';
import 'package:flutter/widgets.dart';

extension ImageProviderExt<T> on ImageProvider {
  /// Pixel dimensions of the image behind this provider.
  ///
  /// The read decodes the image at its stored size, which is larger than any
  /// row draws, so the result leaves the image cache as soon as the size is
  /// known and the caller keeps only the two numbers.
  Future<PixelSize> resolvePixelSize() {
    final completer = Completer<PixelSize>();
    final resolver = resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (image, synchronousCall) {
        completer.complete(
          PixelSize(width: image.image.width, height: image.image.height),
        );
      },
      // A read that fails would otherwise keep the completer pending, and the
      // eviction below would never run.
      onError: completer.completeError,
    );
    resolver.addListener(listener);
    return completer.future.whenComplete(() async {
      resolver.removeListener(listener);
      await evict();
    });
  }
}
