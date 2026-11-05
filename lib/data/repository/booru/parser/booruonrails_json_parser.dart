import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/booru/utils/post_pipeline.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/utils/extensions/pick.dart';
import 'package:collection/collection.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

/// Philomena — the board software behind Derpibooru and Ponybooru, whose API
/// is `/api/v1/json/*` and whose image pages live at `images/{id}`.
///
/// The name here describes the Rails-ness of the URL rather than the name of
/// anything, and it is the one string that cannot change: a saved server keeps
/// [id], so every row already in the box points at this parser through it. The
/// label the user chooses from says Philomena.
class BooruOnRailsJsonParser extends BooruParser {
  @override
  final id = 'BooruOnRails.json';

  @override
  final searchQuery =
      'api/v1/json/search/images?q={tags}&per_page={post-limit}&page={page-num}';

  /// This endpoint has no autocomplete of its own: a bare term must match a
  /// tag name exactly, so the wildcards are what makes it type-ahead. They go
  /// on both sides — a fragment typed in the middle of a name (`book` for
  /// `spellbook`) finds nothing with a leading-only match, which is why the
  /// engines that rank the candidates themselves (Danbooru, Gelbooru) are the
  /// only ones that get away with a bare term.
  @override
  final suggestionQuery = 'api/v1/json/search/tags?q=*{tag-part}*';

  /// The address the site writes into the page it serves for an image. A bare
  /// id asks the app for whatever route that number happens to be, and every
  /// scan still looked like it had found a post page because the boards that
  /// serve this family answer a path they were not given — including the one
  /// being probed — with a page of their own.
  @override
  final postUrl = 'images/{post-id}';

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    return data is Map && BooruUtil.isEntryValue(data['images']);
  }

  @override
  bool isEmptyPayload(Response res) =>
      BooruUtil.isEmptyEnvelope(res.data, 'images');

  @override
  ParsedPage parsePage(Server server, Response res) {
    final entries = BooruUtil.envelopeEntries(res.data, 'images');
    return buildPosts(server, entries, _mapEntry);
  }

  RawPost _mapEntry(Map<String, dynamic> post) {
    final id = pick(post, 'id').asIntOrNull() ?? -1;
    final originalFile = pick(post, 'view_url').asStringOrNull() ?? '';
    final sampleFile =
        pick(post, 'representations', 'large').asStringOrNull() ?? '';
    final previewFile =
        pick(post, 'representations', 'thumb').asStringOrNull() ?? '';
    final tags = pick(post, 'tags').asStringList();
    final width = pick(post, 'width').asIntOrNull(truncateDouble: true) ?? -1;
    final height = pick(post, 'height').asIntOrNull(truncateDouble: true) ?? -1;
    final rating =
        tags
            .where(
              (tag) =>
                  tag == 'explicit' || tag == 'safe' || tag == 'questionable',
            )
            .firstOrNull ??
        '';
    final source = pick(post, 'source_url').asStringOrNull() ?? '';
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
      tags: tags.map(BooruUtil.decodeTag).toList(),
    );
  }

  @override
  bool canParseSuggestion(Response res) {
    final data = res.data;
    return data is Map && BooruUtil.isEntryValue(data['tags']);
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = BooruUtil.envelopeEntries(res.data, 'tags');

    final result = <Suggestion>{};
    for (final entry in entries.whereType<Map<String, dynamic>>()) {
      final tag = pick(entry, 'name').asStringOrNull() ?? '';
      final postCount = pick(entry, 'images').asIntOrNull() ?? 0;
      if (postCount > 0 && tag.isNotEmpty) {
        result.add(Suggestion(BooruUtil.decodeTag(tag), postCount));
      }
    }

    return result;
  }
}
