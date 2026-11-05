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

class DanbooruJsonParser extends BooruParser {
  @override
  final id = 'Danbooru.json';

  @override
  final searchQuery =
      'posts.json?tags={tags}&page={page-num}&limit={post-limit}';

  /// The completion endpoint rather than the tag table.
  ///
  /// `tags.json?search[name_matches]=*…*&search[order]=count` sorts a whole
  /// table of names on every keystroke; `autocomplete.json` is the endpoint the
  /// site built for this exact input and caches per query.
  @override
  final suggestionQuery =
      'autocomplete.json?search[query]={tag-part}&search[type]=tag_query'
      '&limit={post-limit}';

  @override
  final postUrl = 'posts/{post-id}';

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  /// Danbooru documents HTTP Basic for accounts, which keeps the API key out
  /// of every URL in the logs and the history.
  @override
  BooruAuthStyle get authStyle => BooruAuthStyle.basic;

  @override
  bool canParsePage(Response res) {
    final first = _firstEntry(res.data);
    return first != null && first.containsKey('preview_file_url');
  }

  @override
  ParsedPage parsePage(Server server, Response res) {
    final entries = res.data is List ? res.data as List : const [];
    return buildPosts(server, entries, _mapEntry);
  }

  RawPost _mapEntry(Map<String, dynamic> post) {
    final id = pick(post, 'id').asIntOrNull() ?? -1;
    final originalFile = pick(post, 'file_url').asStringOrNull() ?? '';
    final sampleFile = pick(post, 'large_file_url').asStringOrNull() ?? '';
    final previewFile = pick(post, 'preview_file_url').asStringOrNull() ?? '';
    final rating = pick(post, 'rating').asStringOrNull() ?? '';
    final source = pick(post, 'source').asStringOrNull() ?? '';
    final width =
        pick(post, 'image_width').asIntOrNull(truncateDouble: true) ?? -1;
    final height =
        pick(post, 'image_height').asIntOrNull(truncateDouble: true) ?? -1;
    final tags = pick(post, 'tag_string').toWordList();
    final tagsArtist = pick(post, 'tag_string_artist').toWordList();
    final tagsCharacter = pick(post, 'tag_string_character').toWordList();
    final tagsCopyright = pick(post, 'tag_string_copyright').toWordList();
    final tagsGeneral = pick(post, 'tag_string_general').toWordList();
    final tagsMeta = pick(post, 'tag_string_meta').toWordList();
    final score = pick(post, 'score').asIntOrNull() ?? 0;

    return RawPost(
      id: id,
      originalFile: originalFile,
      sampleFile: sampleFile,
      previewFile: previewFile,
      width: width,
      height: height,
      rating: rating,
      source: source,
      score: score,
      // Base tags are intentionally NOT decoded, matching the engine response.
      tags: tags,
      tagsArtist: tagsArtist.map(BooruUtil.decodeTag).toList(),
      tagsCharacter: tagsCharacter.map(BooruUtil.decodeTag).toList(),
      tagsCopyright: tagsCopyright.map(BooruUtil.decodeTag).toList(),
      tagsGeneral: tagsGeneral.map(BooruUtil.decodeTag).toList(),
      tagsMeta: tagsMeta.map(BooruUtil.decodeTag).toList(),
    );
  }

  /// A named tag with a post count, in either of the two shapes the site
  /// reports it in: the tag table keys it by `name`, the completion endpoint by
  /// the `value` it inserts into the search box.
  @override
  bool canParseSuggestion(Response res) {
    final first = _firstEntry(res.data);
    if (first == null) return false;
    return _tagName(first) != null && _tagCount(first) != null;
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = res.data is List ? res.data as List : const [];
    final result = <Suggestion>{};
    for (final entry in entries.whereType<Map<String, dynamic>>()) {
      final rawTag = _tagName(entry);
      final postCount = _tagCount(entry);
      if (rawTag == null || postCount == null) continue;
      final tag = BooruUtil.decodeTag(rawTag);
      final category = tagCategoryFromCode(
        pick(entry, 'category').asIntOrNull(),
      );
      if (postCount > 0 && tag.isNotEmpty) {
        result.add(Suggestion(tag, postCount, category));
      }
    }

    return result;
  }

  String? _tagName(Map entry) {
    return pick(entry, 'name').asStringOrNull() ??
        pick(entry, 'value').asStringOrNull();
  }

  /// The count, whichever key carries it: an older instance spells the field
  /// `num_posts`, and a clone that proxies the tag table hands it over as a
  /// string.
  int? _tagCount(Map entry) {
    for (final key in ['post_count', 'num_posts']) {
      final count = pick(entry, key).asCountOrNull();
      if (count != null) return count;
    }
    return null;
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
      infoUrl: '$base/tags.json?search[name]=$query&limit=1',
      wikiUrl: '$base/wiki_pages/$query.json',
      relatedUrl: '$base/related_tag.json?query=$query',
      aliasUrl:
          '$base/tag_aliases.json?search[antecedent_name]=$query&limit=20',
    );
  }

  @override
  TagInfo? parseTagInfo(String tag, Response res) {
    final data = res.data;
    if (data is! List) return null;

    final entry = _firstEntry(data);
    if (entry == null) return TagInfo(name: tag);

    final name = BooruUtil.decodeTag(
      pick(entry, 'name').asStringOrNull() ?? '',
    );
    return TagInfo(
      name: name.isEmpty ? tag : name,
      category: tagCategoryFromCode(pick(entry, 'category').asIntOrNull()),
      postCount: pick(entry, 'post_count').asIntOrNull(),
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

  @override
  List<TagInfoRelated> parseRelatedTags(Response res) {
    final data = res.data;
    if (data is! Map) return const [];
    final entries = data['related_tags'];
    if (entries is! List) return const [];

    final related = <TagInfoRelated>[];
    for (final entry in entries.whereType<Map>()) {
      final name = BooruUtil.decodeTag(
        pick(entry, 'tag', 'name').asStringOrNull() ?? '',
      );
      if (name.isEmpty) continue;
      related.add(
        TagInfoRelated(
          name,
          pick(entry, 'tag', 'post_count').asIntOrNull() ?? 0,
        ),
      );
    }
    return related.take(20).toList();
  }

  /// The first entry of a JSON array payload, or null when the payload is not
  /// one. Reading the entry here keeps the sniffer total: a payload this engine
  /// cannot read must fall through to the next parser instead of throwing.
  Map? _firstEntry(Object? data) {
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    return first is Map ? first : null;
  }
}
