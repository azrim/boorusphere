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

  @override
  final searchQuery =
      'api/posts/?offset={post-offset}&limit={post-limit}&query={tags}';

  @override
  final suggestionQuery =
      'api/tags/?offset=0&limit={post-limit}&query={tag-part}*';

  @override
  final postUrl = 'post/{post-id}';

  @override
  final headers = {
    'Accept': 'application/json',
    'Content-type': 'application/json',
  };

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    final rawString = data.toString();
    return data is Map &&
        data.containsKey('results') &&
        rawString.contains('contentUrl');
  }

  @override
  ParsedPage parsePage(Server server, Response res) {
    final entries = List.from(res.data['results'] ?? <dynamic>[]);
    return buildPosts(server, entries, _mapEntry);
  }

  RawPost _mapEntry(Map<String, dynamic> post) {
    final id = pick(post, 'id').asIntOrNull() ?? -1;
    final originalFile = pick(post, 'contentUrl').asStringOrNull() ?? '';
    final previewFile = pick(post, 'thumbnailUrl').asStringOrNull() ?? '';
    final width = pick(post, 'canvasWidth').asIntOrNull() ?? -1;
    final height = pick(post, 'canvasHeight').asIntOrNull() ?? -1;
    final rating = pick(post, 'safety').asStringOrNull() ?? '';
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
      rating: rating,
      score: score,
      tags: tags.toList(),
    );
  }

  @override
  bool canParseSuggestion(Response res) {
    final data = res.data;
    final rawString = data.toString();
    return data is Map &&
        data.containsKey('results') &&
        rawString.contains('names');
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = List.from(res.data['results'] ?? <dynamic>[]);
    final result = <Suggestion>{};
    for (final entry in entries.whereType<Map<String, dynamic>>()) {
      final tags = pick(entry, 'names').asListOrEmpty((x) => x.asString());
      final usages = pick(entry, 'usages').asIntOrNull() ?? 0;
      if (usages > 0) {
        result.add(Suggestion(BooruUtil.decodeTag(tags.first), usages));
      }
    }

    return result;
  }
}
