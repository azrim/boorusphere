import 'dart:math';

import 'package:boorusphere/presentation/provider/settings/entity/content_setting.dart';

/// Where the viewer slideshow goes next, or null when it should stop.
///
/// Kept pure so the boundary rules (first/last post, a single-post feed,
/// random never staying on the same page) can be tested without a running
/// viewer. [random] is injected for deterministic tests.
int? nextSlideshowPage({
  required int current,
  required int total,
  required SlideshowDirection direction,
  Random? random,
}) {
  if (total < 2) return null;

  final index = current < 0 ? 0 : (current >= total ? total - 1 : current);

  switch (direction) {
    case SlideshowDirection.forward:
      return index + 1 < total ? index + 1 : null;
    case SlideshowDirection.backward:
      return index > 0 ? index - 1 : null;
    case SlideshowDirection.random:
      final next = (random ?? Random()).nextInt(total - 1);
      return next >= index ? next + 1 : next;
  }
}
