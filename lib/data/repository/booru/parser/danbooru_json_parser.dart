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

class DanbooruJsonParser extends BooruParser {
  @override
  final id = 'Danbooru.json';

  @override
  final searchQuery =
      'posts.json?tags={tags}&page={page-num}&limit={post-limit}';

  @override
  final suggestionQuery =
      'tags.json?search[name_matches]=*{tag-part}*&search[order]=count&limit={post-limit}';

  @override
  final postUrl = 'posts/{post-id}';

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    return data is List &&
        data.isNotEmpty &&
        (data.first as Map).containsKey('preview_file_url');
  }

  @override
  ParsedPage parsePage(Server server, Response res) {
    final entries = List.from(res.data);
    return buildPosts(server, entries, _mapEntry);
  }

  RawPost _mapEntry(Map<String, dynamic> post) {
    final id = pick(post, 'id').asIntOrNull() ?? -1;
    final originalFile = pick(post, 'file_url').asStringOrNull() ?? '';
    final sampleFile = pick(post, 'large_file_url').asStringOrNull() ?? '';
    final previewFile = pick(post, 'preview_file_url').asStringOrNull() ?? '';
    final rating = pick(post, 'rating').asStringOrNull() ?? '';
    final source = pick(post, 'source').asStringOrNull() ?? '';
    final width = pick(post, 'image_width').asIntOrNull() ?? -1;
    final height = pick(post, 'image_height').asIntOrNull() ?? -1;
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

  @override
  bool canParseSuggestion(Response res) {
    final data = res.data;
    return data is List &&
        data.isNotEmpty &&
        (data.first as Map).containsKey('name') &&
        (data.first as Map).containsKey('post_count');
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = List.from(res.data);
    final result = <Suggestion>{};
    for (final Map<String, dynamic> entry in entries) {
      final tag = pick(entry, 'name').asStringOrNull() ?? '';
      final postCount = pick(entry, 'post_count').asIntOrNull() ?? 0;
      if (postCount > 0 && tag.isNotEmpty) {
        result.add(Suggestion(BooruUtil.decodeTag(tag), postCount));
      }
    }

    return result;
  }
}
