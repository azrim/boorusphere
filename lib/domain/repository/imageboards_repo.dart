import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/parsed_page.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';

abstract interface class ImageboardRepo {
  Server get server;
  Future<Iterable<Suggestion>> getSuggestion(String query);
  Future<ParsedPage> getPage(PageOption option, int index);

  /// Describes [tag] as far as this engine publishes: category, post count,
  /// a short wiki, aliases and related tags. Fields the engine does not expose
  /// stay empty. Throws [BooruError.tagInfoUnsupported] for an engine whose
  /// tag endpoint has never been observed.
  Future<TagInfo> getTagInfo(String tag);
}
