/// Category a booru assigns to a tag.
///
/// Only engines whose suggestion payload actually reports the category are
/// mapped. An engine that omits it leaves `Suggestion.category` null instead of
/// guessing from the tag name.
enum TagCategory { general, artist, copyright, character, meta }

/// Maps the numeric category code shared by Danbooru, Moebooru and Gelbooru.
///
/// Code `2` is unused by those engines and code `6` marks a deprecated
/// Gelbooru tag, so both answer null, and so does an engine that omits the field.
TagCategory? tagCategoryFromCode(int? code) {
  return switch (code) {
    0 => TagCategory.general,
    1 => TagCategory.artist,
    3 => TagCategory.copyright,
    4 => TagCategory.character,
    5 => TagCategory.meta,
    _ => null,
  };
}
