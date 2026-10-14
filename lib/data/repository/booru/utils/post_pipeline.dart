import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_util.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';

/// Turns raw parser entries into [Post]s through the shared normalization
/// pipeline.
///
/// Each entry is mapped by [mapEntry] into a [RawPost], then:
/// 1. entries failing the file/content guard (`originalFile` + `previewFile`
///    non-empty, positive `width`/`height`) are skipped;
/// 2. de-duplication is applied per response, keyed by id, marking an id only
///    once its entry has passed the guard (first guard-passing entry wins);
/// 3. media URLs are normalized against [server], the post URL is derived from
///    the id, and an empty rating falls back to `'q'`.
List<Post> buildPosts(
  Server server,
  Iterable<Object?> entries,
  RawPost Function(Map<String, dynamic> entry) mapEntry,
) {
  final result = <Post>[];
  final seenIds = <int>{};
  for (final entry in entries.whereType<Map<String, dynamic>>()) {
    final raw = mapEntry(entry);
    final hasFile = raw.originalFile.isNotEmpty && raw.previewFile.isNotEmpty;
    final hasContent = raw.width > 0 && raw.height > 0;
    if (!hasFile || !hasContent) continue;
    if (!seenIds.add(raw.id)) continue;
    result.add(
      Post(
        id: raw.id,
        originalFile: BooruUtil.normalizeUrl(server, raw.originalFile),
        sampleFile: BooruUtil.normalizeUrl(server, raw.sampleFile),
        previewFile: BooruUtil.normalizeUrl(server, raw.previewFile),
        tags: raw.tags,
        width: raw.width,
        height: raw.height,
        sampleWidth: raw.sampleWidth,
        sampleHeight: raw.sampleHeight,
        previewWidth: raw.previewWidth,
        previewHeight: raw.previewHeight,
        serverId: server.id,
        postUrl: server.postUrlOf(raw.id),
        rateValue: raw.rating.isEmpty ? 'q' : raw.rating,
        source: raw.source,
        tagsArtist: raw.tagsArtist,
        tagsCharacter: raw.tagsCharacter,
        tagsCopyright: raw.tagsCopyright,
        tagsGeneral: raw.tagsGeneral,
        tagsMeta: raw.tagsMeta,
        score: raw.score,
      ),
    );
  }
  return result;
}
