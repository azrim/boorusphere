import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/booru/utils/dtext_summary.dart';
import 'package:boorusphere/data/repository/booru/utils/post_pipeline.dart';
import 'package:boorusphere/data/repository/booru/utils/tag_alias_payload.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/utils/extensions/pick.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

class E621JsonParser extends BooruParser {
  @override
  final id = 'E621.json';

  /// The site's own completion endpoint: it answers the same tag records the
  /// tag table does, from a query built to run on every keystroke.
  @override
  final suggestionQuery =
      'tags/autocomplete.json?search[name_matches]={tag-part}';

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  @override
  bool canParseSuggestion(Response res) {
    final first = _firstSuggestionEntry(res.data);
    return first != null &&
        pick(first, 'name').asStringOrNull() != null &&
        pick(first, 'post_count').asCountOrNull() != null;
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = res.data is List ? res.data as List : const [];
    final result = <Suggestion>{};
    for (final entry in entries.whereType<Map>()) {
      final tag = BooruUtil.decodeTag(
        pick(entry, 'name').asStringOrNull() ?? '',
      );
      final postCount = pick(entry, 'post_count').asCountOrNull() ?? 0;
      if (postCount > 0 && tag.isNotEmpty) {
        result.add(
          Suggestion(
            tag,
            postCount,
            _categoryFromCode(pick(entry, 'category').asIntOrNull()),
          ),
        );
      }
    }

    return result;
  }

  Map? _firstSuggestionEntry(Object? data) {
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    return first is Map ? first : null;
  }

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    // Handle both old format {'posts': [...]} and new format [...]
    if (data is Map) return data['posts'] is List;
    if (data is List && data.isNotEmpty && data.first is Map) {
      // Check if it looks like E621 data (has 'file' and 'tags' keys)
      final first = data.first as Map;
      return first.containsKey('file') && first.containsKey('tags');
    }
    return false;
  }

  @override
  bool isEmptyPayload(Response res) =>
      BooruUtil.isEmptyEnvelope(res.data, 'posts');

  @override
  ParsedPage parsePage(Server server, Response res) {
    // Handle both old format {'posts': [...]} and new format [...]
    final data = res.data;
    final entries = data is List
        ? data
        : BooruUtil.envelopeEntries(data, 'posts');
    return buildPosts(server, entries, _mapEntry);
  }

  RawPost _mapEntry(Map<String, dynamic> post) {
    final id = pick(post, 'id').asIntOrNull() ?? -1;
    final fileMap = pick(post, 'file').asMapOrEmpty();
    final sampleMap = pick(post, 'sample').asMapOrEmpty();
    final previewMap = pick(post, 'preview').asMapOrEmpty();
    final tagsMap = pick(post, 'tags').asMapOrEmpty();

    final originalFile = pick(fileMap, 'url').asStringOrNull() ?? '';
    final sampleFile = pick(sampleMap, 'url').asStringOrNull() ?? '';
    final previewFile = pick(previewMap, 'url').asStringOrNull() ?? '';
    final tagsArtist = pick(tagsMap, 'artist').asStringList();
    final tagsCharacter = pick(tagsMap, 'character').asStringList();
    final tagsCopyright = pick(tagsMap, 'copyright').asStringList();
    final tagsMeta = pick(tagsMap, 'meta').asStringList();
    final tagsGeneral = [
      ...pick(tagsMap, 'general').asStringList(),
      ...pick(tagsMap, 'lore').asStringList(),
      ...pick(tagsMap, 'species').asStringList(),
    ];
    final width = pick(fileMap, 'width').asIntOrNull(truncateDouble: true) ?? 0;
    final height =
        pick(fileMap, 'height').asIntOrNull(truncateDouble: true) ?? 0;
    final sampleWidth =
        pick(sampleMap, 'width').asIntOrNull(truncateDouble: true) ?? 0;
    final sampleHeight =
        pick(sampleMap, 'height').asIntOrNull(truncateDouble: true) ?? 0;
    final previewWidth =
        pick(previewMap, 'width').asIntOrNull(truncateDouble: true) ?? 0;
    final previewHeight =
        pick(previewMap, 'height').asIntOrNull(truncateDouble: true) ?? 0;
    final rating = pick(post, 'rating').asStringOrNull() ?? '';
    final sources = pick(post, 'sources').asStringList();
    final source = sources.isNotEmpty ? sources.first : '';
    final score = pick(post, 'score', 'total').asIntOrNull() ?? 0;

    return RawPost(
      id: id,
      originalFile: originalFile,
      sampleFile: sampleFile,
      previewFile: previewFile,
      width: width,
      height: height,
      sampleWidth: sampleWidth,
      sampleHeight: sampleHeight,
      previewWidth: previewWidth,
      previewHeight: previewHeight,
      rating: rating,
      source: source,
      score: score,
      tagsArtist: tagsArtist.map(BooruUtil.decodeTag).toList(),
      tagsCharacter: tagsCharacter.map(BooruUtil.decodeTag).toList(),
      tagsCopyright: tagsCopyright.map(BooruUtil.decodeTag).toList(),
      tagsGeneral: tagsGeneral.map(BooruUtil.decodeTag).toList(),
      tagsMeta: tagsMeta.map(BooruUtil.decodeTag).toList(),
    );
  }

  @override
  bool get canServeTagInfo => true;

  @override
  bool matchesSearchUrl(String searchUrl) => searchUrl.contains('posts.json');

  @override
  TagInfoRequest? tagInfoRequest(Server server, String tag) {
    final base = server.apiAddress.replaceFirst(RegExp(r'/+$'), '');
    final query = Uri.encodeComponent(tag);
    return TagInfoRequest(
      infoUrl: '$base/tags/$query.json',
      wikiUrl: '$base/wiki_pages/$query.json',
      aliasUrl:
          '$base/tag_aliases.json?search[antecedent_name]=$query&limit=20',
    );
  }

  @override
  TagInfo? parseTagInfo(String tag, Response res) {
    final data = res.data;
    if (data is! Map) return null;

    final entry = data['tag'] is Map ? data['tag'] as Map : data;
    final name = pick(entry, 'name').asStringOrNull();
    if (name == null) return null;

    final related = _relatedFromString(
      pick(entry, 'related_tags').asStringOrNull() ?? '',
    );
    return TagInfo(
      name: name.isEmpty ? tag : BooruUtil.decodeTag(name),
      category: _categoryFromCode(pick(entry, 'category').asIntOrNull()),
      // The v2 endpoint renamed `count` to `post_count`; both are read so an
      // older instance still answers with its count.
      postCount:
          pick(entry, 'post_count').asIntOrNull() ??
          pick(entry, 'count').asIntOrNull(),
      related: related,
    );
  }

  @override
  String parseTagWiki(Response res) {
    final data = res.data;
    if (data is! Map) return '';
    return dtextSummary(pick(data, 'body').asStringOrNull() ?? '');
  }

  @override
  List<String> parseTagAliases(Response res) => tagAliasNamesFrom(res.data);

  /// E621 grades a tag with its own category set: it adds species and lore,
  /// and code 7 is this engine's meta. Species and lore describe the artwork
  /// itself, so they are folded into general rather than mislabelled as meta.
  TagCategory? _categoryFromCode(int? code) {
    return switch (code) {
      0 || 5 || 8 => TagCategory.general,
      1 => TagCategory.artist,
      3 => TagCategory.copyright,
      4 => TagCategory.character,
      7 => TagCategory.meta,
      _ => null,
    };
  }

  /// Reads the `name count name count …` string the tag endpoint reports as
  /// `related_tags`.
  List<TagInfoRelated> _relatedFromString(String raw) {
    final tokens = raw
        .split(RegExp(r'\s+'))
        .where((it) => it.isNotEmpty)
        .toList();
    final related = <TagInfoRelated>[];
    for (var i = 0; i + 1 < tokens.length; i += 2) {
      final name = BooruUtil.decodeTag(tokens[i]);
      final count = int.tryParse(tokens[i + 1]) ?? 0;
      if (name.isNotEmpty) related.add(TagInfoRelated(name, count));
    }
    return related.take(20).toList();
  }
}
