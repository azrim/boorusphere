import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/booru/utils/post_pipeline.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

class SzurubooruJsonParser extends BooruParser {
  @override
  final id = 'Szurubooru.json';

  /// The collection routes, without the trailing slash a hand-written copy of
  /// the template carried: this server's routes are matched exactly, so the
  /// slashed path answers nothing. The engine list users pick from always asked
  /// for the unslashed one, which is why a manual add worked where a scan did
  /// not.
  @override
  final searchQuery =
      'api/posts?offset={post-offset}&limit={post-limit}&query={tags}';

  @override
  final suggestionQuery =
      'api/tags?offset=0&limit={post-limit}&query={tag-part}*';

  @override
  final postUrl = 'post/{post-id}';

  @override
  final headers = {
    'Accept': 'application/json',
    'Content-type': 'application/json',
  };

  /// This server reads only the header: its API has no parameter that takes a
  /// key, so the `user_id`/`api_key` pair this app used to append asked for
  /// nothing and a private instance answered as an anonymous request. The
  /// scheme is the one its own clients send — base64 of `login:api_key` under
  /// the name `Token`.
  @override
  BooruAuthStyle get authStyle => BooruAuthStyle.token;

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  /// The collection route this server serves its posts from.
  ///
  /// A server carrying no parser id is matched by its search URL, so a private
  /// instance is still signed with the header its engine reads instead of the
  /// query pair it never looks at.
  @override
  bool matchesSearchUrl(String searchUrl) => searchUrl.contains('api/posts');

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    final rawString = data.toString();
    return data is Map &&
        BooruUtil.isEntryValue(data['results']) &&
        rawString.contains('contentUrl');
  }

  @override
  bool isEmptyPayload(Response res) =>
      BooruUtil.isEmptyEnvelope(res.data, 'results');

  @override
  ParsedPage parsePage(Server server, Response res) {
    final entries = BooruUtil.envelopeEntries(res.data, 'results');
    return buildPosts(server, entries, _mapEntry);
  }

  RawPost _mapEntry(Map<String, dynamic> post) {
    final id = pick(post, 'id').asIntOrNull() ?? -1;
    final originalFile = pick(post, 'contentUrl').asStringOrNull() ?? '';
    final previewFile = pick(post, 'thumbnailUrl').asStringOrNull() ?? '';
    final width =
        pick(post, 'canvasWidth').asIntOrNull(truncateDouble: true) ?? -1;
    final height =
        pick(post, 'canvasHeight').asIntOrNull(truncateDouble: true) ?? -1;
    final safety = pick(post, 'safety').asStringOrNull() ?? '';
    final score = pick(post, 'score').asIntOrNull() ?? 0;

    final tags = pick(post, 'tags')
        .asListOrEmpty((x) {
          final obj = x.asMapOrEmpty()['names'];
          if (obj is List) {
            return obj.map((e) => BooruUtil.decodeTag(e.toString()));
          }

          return <String>[];
        })
        .fold(<String>{}, (x, a) => {...x, ...a});

    return RawPost(
      id: id,
      originalFile: originalFile,
      previewFile: previewFile,
      width: width,
      height: height,
      rating: _mapSafety(safety),
      score: score,
      tags: tags.toList(),
    );
  }

  /// Szurubooru grades content as `safe`/`sketchy`/`unsafe`, while a post's
  /// rating is stored in the `s`/`q`/`e` spelling used elsewhere. An unknown
  /// grade stays empty so the pipeline applies its own fallback.
  String _mapSafety(String safety) {
    return switch (safety) {
      'safe' => 's',
      'sketchy' => 'q',
      'unsafe' => 'e',
      _ => '',
    };
  }

  @override
  bool canParseSuggestion(Response res) {
    final data = res.data;
    final rawString = data.toString();
    return data is Map &&
        BooruUtil.isEntryValue(data['results']) &&
        rawString.contains('names');
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = BooruUtil.envelopeEntries(res.data, 'results');
    final result = <Suggestion>{};
    for (final entry in entries.whereType<Map<String, dynamic>>()) {
      final tags = pick(entry, 'names').asListOrEmpty((x) => x.asString());
      final usages = pick(entry, 'usages').asIntOrNull() ?? 0;
      if (usages > 0 && tags.isNotEmpty) {
        result.add(Suggestion(BooruUtil.decodeTag(tags.first), usages));
      }
    }

    return result;
  }
}
