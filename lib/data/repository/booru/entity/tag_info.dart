import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';

/// What a server can report about one tag.
///
/// Fields are optional because engines differ: one has a wiki and an alias
/// list, another only knows a post count, and a third has no readable tag
/// endpoint at all. An engine fills what it can prove and leaves the rest out
/// instead of guessing.
class TagInfo {
  const TagInfo({
    required this.name,
    this.category,
    this.postCount,
    this.wiki = '',
    this.aliases = const [],
    this.related = const [],
  });

  /// The name the server reports, or the requested tag when the engine had no
  /// entry to describe it.
  final String name;

  /// The category the server assigns, or null when the engine does not say.
  final TagCategory? category;

  /// How many posts carry the tag, when the engine reports a count.
  final int? postCount;

  /// A short plain-text summary of the engine's wiki page; empty when there is
  /// none or the page carries no body.
  final String wiki;

  /// Other names the server maps to this tag.
  final List<String> aliases;

  /// Tags used alongside this one, most common first.
  final List<TagInfoRelated> related;

  bool get hasDetails =>
      category != null ||
      postCount != null ||
      wiki.isNotEmpty ||
      aliases.isNotEmpty ||
      related.isNotEmpty;
}

/// One tag the engine associates with the tag being read.
class TagInfoRelated {
  const TagInfoRelated(this.name, this.postCount);

  final String name;
  final int postCount;
}

/// The requests one engine needs to describe a tag.
///
/// [infoUrl] carries the entry itself; the rest are best-effort, and a sheet
/// still opens when an engine has no wiki, alias or relation endpoint.
class TagInfoRequest {
  const TagInfoRequest({
    required this.infoUrl,
    this.wikiUrl,
    this.relatedUrl,
    this.aliasUrl,
  });

  final String infoUrl;
  final String? wikiUrl;
  final String? relatedUrl;
  final String? aliasUrl;
}
