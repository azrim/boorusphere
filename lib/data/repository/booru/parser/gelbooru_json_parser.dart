import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/booru/utils/post_pipeline.dart';
import 'package:boorusphere/data/repository/booru/utils/xml_entry.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/utils/extensions/pick.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

class GelbooruJsonParser extends BooruParser {
  @override
  final id = 'Gelbooru.json';

  @override
  final searchQuery =
      'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}&json=1';

  @override
  final suggestionQuery =
      'index.php?page=dapi&s=tag&q=index&name_pattern=%{tag-part}%&orderby=count&limit={post-limit}&json=1';

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    return data is Map && BooruUtil.isEntryValue(data['post']);
  }

  @override
  bool isEmptyPayload(Response res) {
    final data = res.data;
    if (data is! Map) return false;
    // With no entries the DAPI answers with the `@attributes` envelope alone,
    // the `post` key is simply absent.
    if (data.containsKey('@attributes') && !data.containsKey('post')) {
      return true;
    }
    return BooruUtil.isEmptyEnvelope(data, 'post');
  }

  @override
  ParsedPage parsePage(Server server, Response res) {
    final entries = BooruUtil.envelopeEntries(res.data, 'post');
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
    final rating = pick(post, 'rating').asStringOrNull() ?? '';
    final source = pick(post, 'source').asStringOrNull() ?? '';
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
    return data is Map && BooruUtil.isEntryValue(data['tag']);
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = BooruUtil.envelopeEntries(res.data, 'tag');

    final result = <Suggestion>{};
    for (final entry in entries.whereType<Map<String, dynamic>>()) {
      final tag = pick(entry, 'name').asStringOrNull() ?? '';
      final postCount = pick(entry, 'count').asIntOrNull() ?? 0;
      final category = tagCategoryFromCode(pick(entry, 'type').asIntOrNull());
      if (postCount > 0 && tag.isNotEmpty) {
        result.add(Suggestion(BooruUtil.decodeTag(tag), postCount, category));
      }
    }

    return result;
  }

  // The Gelbooru family shares one DAPI, and several members answer XML even
  // when JSON is asked for. The capability therefore lives here, reads both
  // shapes, and is picked by URL for presets that configure the XML parser.
  @override
  bool get canServeTagInfo => true;

  @override
  bool matchesSearchUrl(String searchUrl) =>
      searchUrl.contains('page=dapi') && searchUrl.contains('s=post');

  @override
  TagInfoRequest? tagInfoRequest(Server server, String tag) {
    final base = server.apiAddress.replaceFirst(RegExp(r'/+$'), '');
    final query = Uri.encodeComponent(tag);
    // The JSON flag is carried along only when the server is already asking
    // for it; the endpoint answers both shapes either way.
    final json = server.searchUrl.contains('json=1') ? '&json=1' : '';
    return TagInfoRequest(
      infoUrl:
          '$base/index.php?page=dapi&s=tag&q=index&name=$query&limit=1$json',
    );
  }

  @override
  TagInfo? parseTagInfo(String tag, Response res) {
    final data = res.data;
    final List<Object?> entries;
    if (data is Map) {
      entries = BooruUtil.envelopeEntries(data, 'tag');
    } else {
      final parsed = xmlEntries(data, 'tag');
      if (parsed == null) return null;
      entries = parsed;
    }

    if (entries.isEmpty) return TagInfo(name: tag);
    final entry = entries.first;
    if (entry is! Map) return TagInfo(name: tag);

    final name = BooruUtil.decodeTag(
      pick(entry, 'name').asStringOrNull() ?? '',
    );
    return TagInfo(
      name: name.isEmpty ? tag : name,
      category: tagCategoryFromCode(pick(entry, 'type').asIntOrNull()),
      postCount: pick(entry, 'count').asIntOrNull(),
    );
  }
}
