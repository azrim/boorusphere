import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/booru/tag_info_cache.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tag_info_state.g.dart';

/// One tag on one server: the family argument and the cache key together.
///
/// Tag names are compared case-insensitively, so the same tag opened twice
/// with a different casing is one request and one sheet state.
class TagInfoQuery {
  const TagInfoQuery({required this.serverId, required this.tag});

  final String serverId;
  final String tag;

  String get normalizedTag => tag.trim().toLowerCase();

  @override
  bool operator ==(Object other) =>
      other is TagInfoQuery &&
      other.serverId == serverId &&
      other.normalizedTag == normalizedTag;

  @override
  int get hashCode => Object.hash(serverId, normalizedTag);
}

/// The sheet reports a failure and offers its own retry, so a background
/// retry would only keep the spinner up and repeat a request the server
/// already refused.
Duration? _noRetry(int retryCount, Object error) => null;

/// Describes [TagInfoQuery.tag] through the server's own API, remembering the
/// answer for the next open.
///
/// The cache is consulted before the repo so a revisit paints without a
/// request; a failure is never cached, and [TagInfoCache.remove] lets an
/// explicit retry ask the server again.
@Riverpod(retry: _noRetry)
Future<TagInfo> tagInfo(Ref ref, TagInfoQuery query) async {
  final server = ref.watch(serverStateProvider).getById(query.serverId);
  if (server == Server.empty) throw BooruError.tagInfoUnsupported;

  final cache = ref.read(tagInfoCacheProvider);
  final cached = cache.get(server.id, query.tag);
  if (cached != null) return cached;

  final info = await ref
      .read(imageboardRepoProvider(server))
      .getTagInfo(query.tag);
  cache.put(server.id, query.tag, info);
  return info;
}
