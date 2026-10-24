import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_ce/hive.dart';

part 'server.freezed.dart';
part 'server.g.dart';

@freezed
@HiveType(typeId: 2, adapterName: 'ServerAdapter')
abstract class Server with _$Server {
  const factory Server({
    @HiveField(0, defaultValue: '') @Default('') String id,
    @HiveField(1, defaultValue: '') @Default('') String homepage,
    @HiveField(2, defaultValue: '') @Default('') String postUrl,
    @HiveField(3, defaultValue: '') @Default('') String searchUrl,
    @HiveField(4, defaultValue: '') @Default('') String apiAddr,
    @HiveField(7, defaultValue: '') @Default('') String tagSuggestionUrl,
    @HiveField(8, defaultValue: '') @Default('') String alias,
    @HiveField(9, defaultValue: '') @Default('') String searchParserId,
    @HiveField(10, defaultValue: '') @Default('') String suggestionParserId,
    @HiveField(11, defaultValue: '') @Default('') String login,
    @HiveField(12, defaultValue: '') @Default('') String apiKey,
  }) = _Server;

  factory Server.fromJson(Map<String, dynamic> json) => _$ServerFromJson(json);

  const Server._();

  bool get canSuggestTags => tagSuggestionUrl.contains('{tag-part}');

  String searchUrlOf(PageOption option, {required int page}) {
    final query = option.query.trim();
    // An empty query means "no tag filter". Sending a wildcard instead makes
    // some engines (Gelbooru) scan the whole tag table before answering.
    var tags = query;
    if (searchUrl.toUri().queryParameters.containsKey('offset')) {
      // Szurubooru has exclusive-way (but still same shit) of rating
      tags += ' ${_szuruRateString(option.searchRating)}';
    } else if (searchUrl.contains('api/v1/json/search')) {
      // booru-on-rails didn't support rating
      tags = tags.replaceAll(RegExp(r'\brating:\S+'), '');
    } else {
      tags += ' ${_rateString(option.searchRating)}';
    }
    // Dropping a token leaves a double space behind, which reads as a
    // separator between two empty tags on some engines.
    tags = Uri.encodeComponent(tags.replaceAll(RegExp(r'\s+'), ' ').trim());

    var url = '$apiAddress/$searchUrl'
        .replaceAll('{tags}', tags)
        // Engines number pages differently: `pid` is a zero-based page index,
        // while Danbooru and its clones take a one-based `page`.
        .replaceAll('{page-id}', '$page')
        .replaceAll('{page-num}', '${page + 1}')
        .replaceAll('{post-offset}', (page * option.limit).toString())
        .replaceAll('{post-limit}', '${option.limit}');

    return appendCredentials(url);
  }

  /// Appends the configured credentials to [url].
  ///
  /// The query string is copied as text instead of being parsed and rebuilt:
  /// templates such as `name_pattern=%{tag-part}%` carry a literal `%`, and
  /// decoding the query would read it as the start of a percent escape and
  /// throw [FormatException].
  String appendCredentials(String url) {
    if (!hasCredentials) return url;

    final buffer = StringBuffer(url);
    var separator = url.contains('?')
        ? (url.endsWith('?') || url.endsWith('&') ? '' : '&')
        : '?';
    if (login.isNotEmpty) {
      buffer.write('${separator}user_id=${Uri.encodeComponent(login)}');
      separator = '&';
    }
    if (apiKey.isNotEmpty) {
      buffer.write('${separator}api_key=${Uri.encodeComponent(apiKey)}');
    }

    return buffer.toString();
  }

  String suggestionUrlsOf(String query) {
    var url = '$apiAddress/$tagSuggestionUrl'
        .replaceAll('{post-limit}', '$tagSuggestionLimit')
        .replaceAll('{tag-limit}', '$tagSuggestionLimit');

    final encq = Uri.encodeComponent(query);
    if (!canSuggestTags) {
      throw Exception('no suggestion config for server $name');
    }

    if (query.isEmpty) {
      if (url.contains('name_pattern=') || url.contains('?q=')) {
        url = url.replaceAll(RegExp(r'[*%]*{tag-part}[*%]*'), '');
      } else {
        url = url.replaceAll(RegExp(r'[*%]*{tag-part}[*%]*'), '*');
      }
    } else {
      url = url.replaceAll('{tag-part}', encq);
    }

    return appendCredentials(url);
  }

  String postUrlOf(int id) {
    if (postUrl.isEmpty) {
      return homepage;
    }

    final query = postUrl.replaceAll('{post-id}', id.toString());
    return '$homepage/$query';
  }

  // Key used in hive box
  String get key {
    final asKey = id.replaceAll(RegExp('[^A-Za-z0-9]'), '-');
    return '@${asKey.toLowerCase()}';
  }

  String get apiAddress => apiAddr.isEmpty ? homepage : apiAddr;

  String get name => alias.isNotEmpty ? alias : id;

  /// Returns true if API credentials (login or apiKey) are configured
  bool get hasCredentials => login.isNotEmpty || apiKey.isNotEmpty;

  static const Server empty = Server();
  static const tagSuggestionLimit = 20;
}

String _rateString(BooruRating searchRating) {
  return switch (searchRating) {
    BooruRating.safe => 'rating:safe',
    BooruRating.questionable => 'rating:questionable',
    BooruRating.explicit => 'rating:explicit',
    BooruRating.sensitive => 'rating:sensitive',
    _ => '',
  };
}

String _szuruRateString(BooruRating searchRating) {
  return switch (searchRating) {
    BooruRating.safe => 'safety:safe',
    BooruRating.questionable => 'safety:sketchy',
    BooruRating.sensitive || BooruRating.explicit => 'safety:unsafe',
    _ => '',
  };
}
