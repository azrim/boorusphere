import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/booru/utils/post_pipeline.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/utils/extensions/pick.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

class E621JsonParser extends BooruParser {
  @override
  final id = 'E621.json';

  @override
  List<BooruParserType> get type => [BooruParserType.search];

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    // Handle both old format {'posts': [...]} and new format [...]
    if (data is Map && data.keys.contains('posts')) return true;
    if (data is List && data.isNotEmpty && data.first is Map) {
      // Check if it looks like E621 data (has 'file' and 'tags' keys)
      final first = data.first as Map;
      return first.containsKey('file') && first.containsKey('tags');
    }
    return false;
  }

  @override
  ParsedPage parsePage(Server server, Response res) {
    // Handle both old format {'posts': [...]} and new format [...]
    final data = res.data;
    final entries = switch (data) {
      {'posts': final List posts} => posts,
      List posts => posts,
      _ => <dynamic>[],
    };
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
    final width = pick(fileMap, 'width').asIntOrNull() ?? 0;
    final height = pick(fileMap, 'height').asIntOrNull() ?? 0;
    final sampleWidth = pick(sampleMap, 'width').asIntOrNull() ?? 0;
    final sampleHeight = pick(sampleMap, 'height').asIntOrNull() ?? 0;
    final previewWidth = pick(previewMap, 'width').asIntOrNull() ?? 0;
    final previewHeight = pick(previewMap, 'height').asIntOrNull() ?? 0;
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
}
