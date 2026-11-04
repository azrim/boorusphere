import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/booru/utils/post_pipeline.dart';
import 'package:boorusphere/data/repository/booru/utils/xml_entry.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/utils/extensions/pick.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

class ShimmieXmlParser extends BooruParser {
  @override
  final id = 'Shimmie.xml';

  @override
  final postUrl = 'post/view/{post-id}';

  /// The `danbooru_api` extension answers under its clean path. The
  /// `/index.xml` suffix it once needed now resolves to the site's error page.
  @override
  final searchQuery =
      'api/danbooru/find_posts?tags={tags}&limit={post-limit}&page={page-num}';

  @override
  final suggestionQuery = 'api/internal/autocomplete?s={tag-part}';

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    // Both entry spellings carry the file URL the reader needs. Requiring it
    // keeps a `<posts>` set whose attributes this engine has since renamed with
    // the unparsable path: claiming it would answer "no results" for a page
    // that plainly has posts, and pagination would stop on a live query.
    return data is String &&
        data.contains('<posts') &&
        _entryShape.hasMatch(data);
  }

  static final _entryShape = RegExp(
    r'''<(post|tag)\s[^>]*\bfile_url\s*=['"]''',
  );

  @override
  bool isEmptyPayload(Response res) => xmlIsEmptyResultSet(res.data);

  @override
  ParsedPage parsePage(Server server, Response res) {
    // The extension renamed its entry element along the way: older installs
    // wrapped every post in a `<tag>`, current ones in a `<post>`. The
    // attributes are the same, so both feed one reader.
    final posts = xmlEntries(res.data, 'post');
    if (posts == null) throw BooruError.unparsable;

    final entries = posts.isNotEmpty ? posts : xmlEntries(res.data, 'tag');
    if (entries == null) throw BooruError.unparsable;

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
  bool canParseSuggestion(Response res) => _suggestionCounts(res.data) != null;

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final counted = _suggestionCounts(res.data) ?? const <String, int>{};
    return counted.entries
        .where((it) => it.value > 0)
        .map((it) => Suggestion(BooruUtil.decodeTag(it.key), it.value))
        .toSet();
  }

  /// The `tag → post count` map, in either shape this engine sends it.
  ///
  /// Older installs put the count directly behind the tag name, current ones
  /// wrap the tag in an object that carries `count` beside its alias
  /// information. A payload that is neither — an envelope, a list — is not this
  /// engine's autocomplete, and saying so leaves it to the parser that can read
  /// it instead of answering with an empty suggestion list.
  Map<String, int>? _suggestionCounts(Object? data) {
    if (data is! Map) return null;

    final counts = <String, int>{};
    for (final entry in data.entries) {
      final tag = entry.key;
      if (tag is! String) return null;

      final value = entry.value;
      final count = _toCount(value is Map ? value['count'] : value);
      if (count == null) return null;
      counts[tag] = count;
    }

    return counts;
  }

  static int? _toCount(Object? value) => switch (value) {
    final int it => it,
    final num it => it.toInt(),
    final String it => int.tryParse(it),
    _ => null,
  };
}
