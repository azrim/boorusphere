import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:flutter/material.dart';

/// Letter and scheme colors for a post rating, shared by the timeline overlay
/// and the search bar indicator so both use the same S / Q / E / SN
/// vocabulary and the same mapping from rating to color role.
///
/// [color] is the tint; [onColor] is the foreground that sits on a solid
/// [color] fill. Unrated ([BooruRating.all]) returns `null`.
({String label, Color color, Color onColor})? ratingBadgeOf(
  BooruRating rating,
  ColorScheme scheme,
) {
  return switch (rating) {
    BooruRating.safe => (
      label: 'S',
      color: scheme.primary,
      onColor: scheme.onPrimary,
    ),
    BooruRating.questionable => (
      label: 'Q',
      color: scheme.tertiary,
      onColor: scheme.onTertiary,
    ),
    BooruRating.explicit => (
      label: 'E',
      color: scheme.error,
      onColor: scheme.onError,
    ),
    // "SN" so it can't be mistaken for the safe "S".
    BooruRating.sensitive => (
      label: 'SN',
      color: scheme.secondary,
      onColor: scheme.onSecondary,
    ),
    BooruRating.all => null,
  };
}
