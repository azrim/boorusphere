import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';
import 'package:flutter/material.dart';

/// Tag category accents following the booru convention (artist orange,
/// copyright purple, character green, general blue).
///
/// These are fixed hues rather than scheme tokens because the same accents are
/// painted straight on arbitrary post images by the timeline chip — the one
/// documented exception to the adaptive-palette rule. Kept here so the timeline
/// and the suggestion list cannot drift apart.
const Color kTagArtistAccent = Color(0xFFFFB74D);
const Color kTagCopyrightAccent = Color(0xFFBA68C8);
const Color kTagCharacterAccent = Color(0xFF81C784);
const Color kTagGeneralAccent = Color(0xFF64B5F6);

extension TagCategoryAccent on TagCategory {
  /// Icon that names the category without relying on its color alone.
  IconData get icon {
    return switch (this) {
      TagCategory.artist => Icons.brush_outlined,
      TagCategory.copyright => Icons.copyright,
      TagCategory.character => Icons.person_outline,
      TagCategory.general => Icons.tag,
      // Meta carries no fixed hue; the neutral scheme color is its accent.
      TagCategory.meta => Icons.info_outline,
    };
  }

  /// The category accent, or a scheme neutral when the category has none.
  Color accentOf(ColorScheme scheme) {
    return switch (this) {
      TagCategory.artist => kTagArtistAccent,
      TagCategory.copyright => kTagCopyrightAccent,
      TagCategory.character => kTagCharacterAccent,
      TagCategory.general => kTagGeneralAccent,
      TagCategory.meta => scheme.onSurfaceVariant,
    };
  }
}
