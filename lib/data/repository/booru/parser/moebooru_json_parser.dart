import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/booru/utils/post_pipeline.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/utils/extensions/pick.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

class MoebooruJsonParser extends BooruParser {
  @override
  final id = 'Moebooru.json';

  @override
  final searchQuery =
      'post.json?tags={tags}&page={page-num}&limit={post-limit}';

  @override
  final suggestionQuery =
      'tag.json?name=*{tag-part}*&order=count&limit={post-limit}';

  @override
  final postUrl = 'post/show/{post-id}';

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    return data is List &&
        data.any((it) => it is Map && it.containsKey('preview_url'));
  }

  @override
  ParsedPage parsePage(Server server, Response res) {
    final entries = res.data is List ? res.data as List : const [];
    return buildPosts(server, entries, _mapEntry);
  }

  RawPost _mapEntry(Map<String, dynamic> post) {
    final id = pick(post, 'id').asIntOrNull() ?? -1;
    final originalFile = pick(post, 'file_url').asStringOrNull() ?? '';
    final sampleFile = pick(post, 'sample_url').asStringOrNull() ?? '';
    final previewFile = pick(post, 'preview_url').asStringOrNull() ?? '';
    final tags = pick(post, 'tags').toWordList();
    final width = pick(post, 'width').asIntOrNull(truncateDouble: true) ?? -1;
    final height = pick(post, 'height').asIntOrNull(truncateDouble: true) ?? -1;
    final sampleWidth =
        pick(post, 'sample_width').asIntOrNull(truncateDouble: true) ?? -1;
    final sampleHeight =
        pick(post, 'sample_height').asIntOrNull(truncateDouble: true) ?? -1;
    final previewWidth =
        pick(post, 'preview_width').asIntOrNull(truncateDouble: true) ?? -1;
    final previewHeight =
        pick(post, 'preview_height').asIntOrNull(truncateDouble: true) ?? -1;
    final source = pick(post, 'source').asStringOrNull() ?? '';
    final rating = pick(post, 'rating').asStringOrNull() ?? '';
    final score = pick(post, 'score').asIntOrNull() ?? 0;

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
      tags: tags.map(BooruUtil.decodeTag).toList(),
    );
  }

  @override
  bool canParseSuggestion(Response res) {
    final data = res.data;
    return data is List &&
        data.any(
          (it) =>
              it is Map && it.containsKey('name') && it.containsKey('count'),
        );
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = res.data is List ? res.data as List : const [];
    final result = <Suggestion>{};
    for (final entry in entries.whereType<Map>()) {
      final tag = pick(entry, 'name').asStringOrNull() ?? '';
      final postCount = pick(entry, 'count').asCountOrNull() ?? 0;
      final category = tagCategoryFromCode(pick(entry, 'type').asIntOrNull());
      if (postCount > 0 && tag.isNotEmpty) {
        result.add(Suggestion(BooruUtil.decodeTag(tag), postCount, category));
      }
    }

    return result;
  }

  @override
  bool get canServeTagInfo => true;

  @override
  bool matchesSearchUrl(String searchUrl) => searchUrl.contains('post.json');

  @override
  TagInfoRequest? tagInfoRequest(Server server, String tag) {
    final base = server.apiAddress.replaceFirst(RegExp(r'/+$'), '');
    final query = Uri.encodeComponent(tag);
    return TagInfoRequest(
      infoUrl: '$base/tag.json?name=$query&limit=20',
      relatedUrl: '$base/tag/related.json?tags=$query',
    );
  }

  @override
  TagInfo? parseTagInfo(String tag, Response res) {
    final data = res.data;
    if (data is! List) return null;

    // `name=` answers every tag whose name contains the query, so the exact
    // one is picked out here.
    final wanted = tag.toLowerCase();
    for (final entry in data.whereType<Map>()) {
      final name = BooruUtil.decodeTag(
        pick(entry, 'name').asStringOrNull() ?? '',
      );
      if (name.toLowerCase() != wanted) continue;

      return TagInfo(
        name: name,
        category: tagCategoryFromCode(pick(entry, 'type').asIntOrNull()),
        postCount: pick(entry, 'count').asIntOrNull(),
      );
    }

    return TagInfo(name: tag);
  }

  @override
  List<TagInfoRelated> parseRelatedTags(Response res) {
    final data = res.data;
    if (data is! Map) return const [];

    // The engine keys the object by the queried tag and holds [name, count]
    // pairs. Only one tag is asked for, so the first pair list is the answer.
    List<Object?>? pairs;
    for (final value in data.values) {
      if (value is List) {
        pairs = value;
        break;
      }
    }
    if (pairs == null) return const [];

    return _relatedTagPairs(pairs);
  }
}

/// Reads the `[name, count]` pairs a Moebooru related-tag answer carries.
List<TagInfoRelated> _relatedTagPairs(List<Object?> pairs) {
  final related = <TagInfoRelated>[];
  for (final pair in pairs) {
    if (pair is! List || pair.length < 2) continue;

    final name = BooruUtil.decodeTag(pair[0]?.toString() ?? '');
    if (name.isEmpty) continue;

    final rawCount = pair[1];
    final count = rawCount is num
        ? rawCount.toInt()
        : int.tryParse(rawCount?.toString() ?? '') ?? 0;
    related.add(TagInfoRelated(name, count));
  }
  return related.take(20).toList();
}
