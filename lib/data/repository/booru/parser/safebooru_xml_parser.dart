import 'dart:collection';
import 'dart:convert';

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
import 'package:xml2json/xml2json.dart';

class SafebooruXmlParser extends BooruParser {
  @override
  final id = 'Safebooru.xml';

  @override
  List<BooruParserType> get type => [
    BooruParserType.search,
    BooruParserType.suggestion,
  ];

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    final rawString = data.toString();
    return data is String &&
        rawString.contains('<?xml') &&
        rawString.contains('<posts ') &&
        rawString.contains('<post ') &&
        rawString.contains(' file_url="');
  }

  @override
  ParsedPage parsePage(Server server, Response res) {
    final entries = [];
    final xjson = Xml2Json();
    xjson.parse(res.data.replaceAll('\\', ''));

    final fromGDataConv = jsonDecode(xjson.toGData());
    if (!fromGDataConv.values.first.keys.contains('post')) {
      return const ParsedPage.empty();
    }

    final posts = fromGDataConv.values.first['post'];

    if (posts is LinkedHashMap) {
      entries.add(posts);
    } else if (posts is List) {
      entries.addAll(posts);
    } else {
      return const ParsedPage.empty();
    }

    return buildPosts(server, entries, _mapEntry);
  }

  RawPost _mapEntry(Map<String, dynamic> post) {
    final id = pick(post, 'id').asIntOrNull() ?? -1;
    final originalFile = pick(post, 'file_url').asStringOrNull() ?? '';
    final sampleFile = pick(post, 'sample_url').asStringOrNull() ?? '';
    final previewFile = pick(post, 'preview_url').asStringOrNull() ?? '';
    final tags = pick(post, 'tags').toWordList();
    final width = pick(post, 'width').asIntOrNull() ?? -1;
    final height = pick(post, 'height').asIntOrNull() ?? -1;
    final sampleWidth = pick(post, 'sample_width').asIntOrNull() ?? -1;
    final sampleHeight = pick(post, 'sample_height').asIntOrNull() ?? -1;
    final previewWidth = pick(post, 'preview_width').asIntOrNull() ?? -1;
    final previewHeight = pick(post, 'preview_height').asIntOrNull() ?? -1;
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
    final rawString = data.toString();
    return data is String &&
        rawString.contains('<?xml') &&
        rawString.contains('<tags') &&
        rawString.contains('<tag ') &&
        rawString.contains(' name="');
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final data = res.data;
    final entries = [];

    final xjson = Xml2Json();
    xjson.parse(data.replaceAll('\\', ''));

    final fromGDataConv = jsonDecode(xjson.toGData());
    if (!fromGDataConv.values.first.keys.contains('tag')) {
      return {};
    }

    final tags = fromGDataConv.values.first['tag'];

    if (tags is LinkedHashMap) {
      entries.add(tags);
    } else if (tags is List) {
      entries.addAll(tags);
    } else {
      return {};
    }

    final result = <Suggestion>{};
    for (final Map<String, dynamic> entry in entries) {
      final tag = pick(entry, 'name').asStringOrNull() ?? '';
      final postCount = pick(entry, 'count').asIntOrNull() ?? 0;
      if (postCount > 0 && tag.isNotEmpty) {
        result.add(Suggestion(BooruUtil.decodeTag(tag), postCount));
      }
    }

    return result;
  }
}
