import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/booru/utils/post_pipeline.dart';
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
      if (postCount > 0 && tag.isNotEmpty) {
        result.add(Suggestion(BooruUtil.decodeTag(tag), postCount));
      }
    }

    return result;
  }
}
