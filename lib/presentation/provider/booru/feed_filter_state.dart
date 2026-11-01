import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'feed_filter_state.g.dart';

/// A post identity that stays unique across servers: a booru post id only
/// means something together with the booru that assigned it.
typedef FeedPostKey = ({String serverId, int id});

FeedPostKey feedPostKeyOf(Post post) {
  return (serverId: post.serverId, id: post.id);
}

/// Posts the local feed filters remove from the timeline.
///
/// Kept as one derived set so the fetch-time skip and the live filter on the
/// already loaded page cannot disagree. Favorites and download records are read
/// from their kept providers; a download only counts once its task finished, so
/// a failed or partial file does not take a post out of the feed.
@Riverpod(keepAlive: true)
Set<FeedPostKey> hiddenFeedPostKeys(Ref ref) {
  final hideFavorited = ref.watch(
    contentSettingStateProvider.select((it) => it.hideFavorited),
  );
  final hideDownloaded = ref.watch(
    contentSettingStateProvider.select((it) => it.hideDownloaded),
  );
  if (!hideFavorited && !hideDownloaded) return const <FeedPostKey>{};

  final keys = <FeedPostKey>{};
  if (hideFavorited) {
    for (final post in ref.watch(favoritePostStateProvider)) {
      keys.add(feedPostKeyOf(post));
    }
  }
  if (hideDownloaded) {
    final entries = ref.watch(downloadEntryStateProvider);
    final progresses = ref.watch(downloadProgressStateProvider);
    for (final entry in entries) {
      if (progresses.getById(entry.id).status.isDownloaded) {
        keys.add(feedPostKeyOf(entry.post));
      }
    }
  }
  return keys;
}
