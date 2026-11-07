import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/tags_blocker/tag_expression.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/entity/page_data.dart';
import 'package:boorusphere/presentation/provider/booru/feed_filter_state.dart';
import 'package:boorusphere/presentation/provider/search_history_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'page_state.g.dart';

/// Outcome of a page fetch: [index] is the 0-based page that was actually
/// loaded (it can differ from the requested one when fully-blocked pages were
/// skipped), [posts] are its displayable posts and [rawCount] is the raw
/// server result count used for the `hasNext` heuristic.
typedef _PageFetch = ({int index, List<Post> posts, int rawCount});

@riverpod
class PageState extends _$PageState {
  PageState({this.session = const SearchSession()});

  final SearchSession session;

  /// Maximum number of consecutive pages that may be skipped when a fetched
  /// page yields no displayable posts (hidden by the tags blocker or rejected
  /// by the content guard).
  static const _maxSkippedPages = 3;

  /// Ceiling for the list infinite mode keeps in memory. Ten pages of sixty
  /// posts, or more when the reader picked a smaller page: an exploration
  /// session that runs for hours must not keep every post it ever saw alive.
  ///
  /// The oldest posts are not evicted from the top (dropping rows above the
  /// reader would move the grid under their thumb), so the loader stops once
  /// the ceiling is reached and the footer asks for a refresh to start over.
  static const maxAccumulatedPosts = 600;

  /// Zero-based page index handed to `ImageboardRepo.getPage` (page `0` is the
  /// first page). [PageData.pageIndex] exposes the same position as a 1-based
  /// value for the UI.
  int _page = 0;

  /// Guards fetches so rapid prev/next taps can't interleave.
  bool _fetching = false;

  /// Option that arrived while a fetch was in flight. The response already on
  /// the wire carries the previous option, so the change is applied once that
  /// fetch settles instead of being dropped.
  PageOption? _pendingOption;

  /// A reload asked for while a fetch was in flight. Unlike [_pendingOption]
  /// it carries no option of its own: it only has to run so the settings read
  /// after the current request landed are applied to the feed.
  bool _reloadPending = false;

  /// Navigation target whose fetch failed, so the next [load] (the retry
  /// button, a pull-to-refresh) resumes the page the user asked for instead of
  /// reloading the one still on screen.
  int? _retryTarget;

  /// A load-more failed in infinite mode. Unlike [_retryTarget] it has to
  /// append the page after the last landed one rather than replace the list:
  /// the posts already on screen are still the ones the reader was scrolling.
  bool _retryAppend = false;

  /// The search this page already counted in the history.
  ///
  /// [load] runs for a pull-to-refresh, a rating change and a filter reload as
  /// well as for the first fetch, and counting each of those inflated the
  /// usage a suggestion row reports. The history counts searches, so only a
  /// query this page has not recorded yet is saved. A repeat of the same query
  /// from the bar opens a new page (and a new notifier), so it still counts.
  ({String query, String serverId})? _recordedSearch;

  @override
  FetchResult<PageData> build() {
    _page = 0;
    _fetching = false;
    _pendingOption = null;
    _reloadPending = false;
    _retryTarget = null;
    _retryAppend = false;
    _recordedSearch = null;
    return const FetchResult.idle(PageData());
  }

  /// How the timeline walks this result set, read per fetch so a mode switch
  /// only needs the page to reload.
  FeedMode get _feedMode => ref.read(uiSettingStateProvider).feedMode;

  Server get _server {
    // A session can outlive its server (the drawer removes one without
    // leaving the page). Resolving that id to the first server instead would
    // answer the next page from a different booru.
    return ref
        .read(serverStateProvider)
        .getById(session.serverId, or: Server.empty);
  }

  /// Reports a session whose server is no longer in the list, which happens
  /// when the drawer removes the server the page was opened with.
  ///
  /// The error is the generic one on purpose: the timeline must not look idle
  /// while every load and navigation quietly does nothing, and the status card
  /// that shows it also carries the "Change server" action that gets out.
  ///
  /// Resolving the server reads storage, so a failure there is reported the
  /// same way as a missing server: an uncaught throw here would leave the feed
  /// at `idle`, which renders no status card at all.
  bool _hasServer() {
    final Server server;
    try {
      server = _server;
    } catch (err, stack) {
      if (!ref.mounted) return false;
      state = FetchResult.error(state.data, error: err, stackTrace: stack);
      return false;
    }
    if (server != Server.empty) return true;
    state = FetchResult.error(state.data);
    return false;
  }

  /// The blockers that apply to [server]: a tag blocked on one booru is still
  /// a usable tag on the others.
  List<BlockedTagExpression> _blockedExpressionsFor(Server server) {
    return parseBlockedTagExpressions(
      ref
          .read(tagsBlockerStateProvider)
          .values
          .where((it) => it.serverId.isEmpty || it.serverId == server.id)
          .map((it) => it.name),
    );
  }

  /// Whether the result window moved between [shown] (the option the displayed
  /// posts were fetched with) and [next]. A different page size or rating
  /// re-indexes the same query, so the landed page no longer points at the
  /// posts the reader is looking at and every walk starts over from page one.
  static bool _windowChanged(PageOption next, PageOption shown) {
    return next.limit != shown.limit || next.searchRating != shown.searchRating;
  }

  /// [data] labeled with the page the arrows act on.
  ///
  /// A restart moves the landed page back to the first one before its request
  /// lands. When that request fails, the data still carries the label of the
  /// page that was on screen, so the page number and the enabled arrows would
  /// point at positions the restarted window does not have.
  PageData _alignPageLabel(PageData data) {
    if (_page != 0) return data;
    if (data.pageIndex == 1 && !data.hasPrev) return data;
    return data.copyWith(pageIndex: 1, hasPrev: false);
  }

  /// [data] with the posts of the previous result window dropped.
  ///
  /// A restart that failed could not replace them, and the new window does not
  /// own them: leaving them on screen would present them as its first page,
  /// with arrows aimed at indexes that address other posts.
  PageData _emptyWindow(PageData data) {
    return data.copyWith(
      posts: const [],
      pageIndex: 1,
      hasPrev: false,
      hasNext: false,
      limitReached: false,
    );
  }

  /// Reports a query that contains a tag blocked on [server], and whether it
  /// did.
  ///
  /// The query can be blocked after it was loaded, so every way into a fetch
  /// runs this check: a page of a blocked query is still a page of that query.
  bool _refuseBlockedQuery(Server server) {
    // Only a plain single-tag entry always hides the tag: an AND/OR/negated
    // entry can still let posts with that tag through, and refusing the query
    // for it would reject a search that has visible results.
    final blocked = <String>{};
    for (final expression in _blockedExpressionsFor(server)) {
      final tag = expression.singlePlainTag;
      if (tag != null) blocked.add(tag);
    }
    if (blocked.isEmpty) return false;

    final query = state.data.option.query;
    if (!query.toWordList().any((it) => blocked.contains(it.toLowerCase()))) {
      return false;
    }
    state = FetchResult.error(state.data, error: BooruError.tagsBlocked);
    return true;
  }

  Future<void> update(PageOption Function(PageOption) updater) async {
    // A change queued during a fetch has not reached [state] yet; building the
    // next one from the committed option would silently drop it.
    final newOption = updater(_pendingOption ?? state.data.option);
    _retryTarget = null;
    _retryAppend = false;
    if (_fetching) {
      _pendingOption = newOption;
      return;
    }
    state = state.copyWith(data: state.data.copyWith(option: newOption));
    await load();
  }

  /// Loads (or reloads) the page currently being displayed.
  ///
  /// Used for the first load, retry and pull-to-refresh. An option marked with
  /// `clear` (a new query) restarts from the first page, and so does a result
  /// window that moved under the posts on screen (another page size or rating).
  Future<void> load() async {
    // A caller can hand this over and the page can be gone by the time it
    // runs (a rating picked while the timeline closes).
    if (!ref.mounted) return;
    if (!_hasServer()) return;
    if (_fetching) {
      // The request on the wire was built from the settings read when it
      // started, so its answer would leave the feed on that window. Run the
      // reload once the fetch settles.
      _reloadPending = true;
      return;
    }

    final server = _server;
    if (_refuseBlockedQuery(server)) return;

    final retry = _retryTarget;
    if (retry != null) {
      await _navigateTo(retry);
      return;
    }
    if (_retryAppend) {
      _retryAppend = false;
      await _appendNextPage();
      return;
    }

    final query = state.data.option.query;
    if (query.isNotEmpty &&
        _recordedSearch != (query: query, serverId: server.id)) {
      _recordedSearch = (query: query, serverId: server.id);
      unawaited(_recordHistory(query, server));
    }
    final settings = ref.read(serverSettingStateProvider);
    final shown = state.data.option;
    final option = shown.copyWith(
      limit: settings.postLimit,
      searchRating: settings.searchRating,
    );

    // A new query restarts the result set, and a window that moved under the
    // posts on screen re-indexes it: either way the landed page must go back
    // to the first one, or the reader is pointed at other posts.
    //
    // Infinite mode has no page to stay on: a reload (pull-to-refresh, a
    // filter change) starts the accumulated list over from its first page.
    final windowChanged = _windowChanged(option, shown);
    final restart =
        option.clear || windowChanged || _feedMode == FeedMode.infinite;

    _fetching = true;
    try {
      if (restart) _page = 0;

      state = FetchResult.loading(state.data.copyWith(option: option));

      var result = await _fetchPage(option, server, _page);
      // The page can be popped while the request is on the wire; the element
      // is gone then and every further write would throw.
      if (!ref.mounted) return;
      if ((result == null || result.posts.isEmpty) && _page > 0) {
        // An empty answer for a deep page only proves that page is past the
        // end (or that every one of its entries is filtered). The window can
        // have shifted under a stale index, so ask for the first page before
        // telling the reader there is nothing to show.
        _page = 0;
        result = await _fetchPage(option, server, 0);
        if (!ref.mounted) return;
      }
      if (result == null || result.posts.isEmpty) {
        // Nothing displayable on the first page. A literal empty response is
        // an empty query; entries the filters removed are a different answer,
        // and the status card names the filter that can bring them back.
        state = FetchResult.error(
          // Posts fetched with the previous window do not belong to the
          // window the reader is in now: keeping them would present them as
          // its first page.
          windowChanged
              ? _emptyWindow(state.data)
              : _alignPageLabel(state.data),
          error: result == null ? BooruError.empty : BooruError.filtered,
        );
        return;
      }

      _page = result.index;
      state = FetchResult.data(
        state.data.copyWith(
          posts: List.unmodifiable(result.posts),
          option: option.copyWith(clear: false),
          pageIndex: result.index + 1,
          // Only a literal empty page proves the end of the results. A page
          // shorter than the requested limit is still followed by more
          // whenever the server clamps its page size.
          hasNext: result.rawCount > 0,
          hasPrev: result.index > 0,
          // A reload starts the result set over, so an in-memory ceiling an
          // earlier list hit says nothing about this one. Leaving the flag set
          // is what used to keep the footer asking for a refresh while the
          // refresh itself kept refusing to grow the list.
          limitReached: false,
          // A reload that starts over can keep the same page index (or land on
          // the first page again), so an append and a restart are told apart by
          // this counter rather than by the index. The feed resets its viewport
          // when it changes; only a restart that landed bumps it, so a failed
          // one leaves the reader where they were.
          restartSerial: restart
              ? state.data.restartSerial + 1
              : state.data.restartSerial,
        ),
      );
    } catch (err, stack) {
      if (!ref.mounted) return;
      state = FetchResult.error(
        windowChanged ? _emptyWindow(state.data) : _alignPageLabel(state.data),
        error: err,
        stackTrace: stack,
      );
    } finally {
      _fetching = false;
      _drainPending();
      _drainReload();
    }
  }

  /// Records the search in the history without letting the write decide the
  /// fate of the page.
  ///
  /// The save used to be awaited inside the fetch's `try`, so a storage
  /// failure turned a perfectly good page request into an error and the page
  /// was never asked for. The record is a convenience: a miss is logged and
  /// dropped, and the page loads either way.
  Future<void> _recordHistory(String query, Server server) async {
    try {
      await ref.read(searchHistoryStateProvider.notifier).save(query, server);
    } catch (err, stack) {
      mainLog.w('PageState: failed to record the search history', err, stack);
    }
  }

  /// Grows the list (infinite mode) or loads the next page, replacing the
  /// currently displayed posts (paged mode).
  Future<void> nextPage() async {
    if (!ref.mounted) return;
    if (_fetching) return;
    if (!state.data.hasNext) return;
    if (state.data.posts.isEmpty) return;
    if (_feedMode == FeedMode.infinite) {
      // The ceiling caps the accumulated list; a paged step replaces the
      // posts, so a flag left behind by an infinite session must not keep
      // the pagination control dead.
      if (state.data.limitReached) return;
      await _appendNextPage();
      return;
    }
    await _navigateTo(_page + 1);
  }

  /// Loads the page after the last landed one and appends it to the list.
  ///
  /// Called by the scroll position as it approaches the end, and by the retry
  /// path; it is a no-op outside infinite mode so a stray trigger cannot grow
  /// a paged feed behind the pagination control.
  Future<void> loadMore() async {
    if (!ref.mounted) return;
    if (_fetching) return;
    if (_feedMode != FeedMode.infinite) return;
    final data = state.data;
    if (!data.hasNext || data.posts.isEmpty || data.limitReached) return;
    await _appendNextPage();
  }

  /// Loads the previous page, replacing the currently displayed posts.
  Future<void> prevPage() async {
    if (!ref.mounted) return;
    if (_fetching) return;
    if (!state.data.hasPrev) return;
    if (_feedMode == FeedMode.infinite) return;
    if (_page <= 0) return;
    if (state.data.posts.isEmpty) return;
    await _navigateTo(_page - 1);
  }

  /// Loads [page] (1-based), replacing the currently displayed posts.
  Future<void> goToPage(int page) async {
    if (!ref.mounted) return;
    if (_fetching) return;
    if (_feedMode == FeedMode.infinite) return;
    if (state.data.posts.isEmpty) return;
    final target = page - 1;
    if (target < 0 || target == _page) return;
    await _navigateTo(target);
  }

  Future<void> _navigateTo(int target) async {
    if (!_hasServer()) return;
    _retryTarget = null;

    final server = _server;
    if (_refuseBlockedQuery(server)) return;

    final current = state.data;
    final settings = ref.read(serverSettingStateProvider);
    final option = current.option.copyWith(
      limit: settings.postLimit,
      searchRating: settings.searchRating,
    );
    // The result window changed while this page was on screen, so the index no
    // longer maps to the same posts. Move the landed page back to the first
    // one as well: leaving it where it was would aim the next step at the old
    // window when this reset fails to land.
    final windowChanged = _windowChanged(option, current.option);
    if (windowChanged) {
      target = 0;
      _page = 0;
    }
    final direction = windowChanged || target >= _page ? 1 : -1;

    _fetching = true;
    try {
      // Keep the currently displayed posts visible while the fetch is in
      // flight so the grid doesn't flash empty.
      state = FetchResult.loading(current.copyWith(option: option));

      final result = await _fetchPage(
        option,
        server,
        target,
        direction: direction,
      );
      if (!ref.mounted) return;
      if (result == null || result.posts.isEmpty) {
        if (windowChanged) {
          // The displayed posts were fetched from the window the reader just
          // left; the reset that would have replaced them did not land. Keep
          // them out of the new window and let the card offer the retry.
          state = FetchResult.error(
            _emptyWindow(
              current.copyWith(option: option.copyWith(clear: false)),
            ),
            error: result == null ? BooruError.empty : BooruError.filtered,
          );
          return;
        }
        // The navigation target has no displayable posts: keep the displayed
        // posts and stay on the current page. Only a failed step to the page
        // right next door proves the end of the results; a jump further ahead
        // says nothing about the neighbour still on offer, and disabling that
        // arrow would strand the reader on this page.
        state = FetchResult.data(
          _alignPageLabel(
            current.copyWith(
              option: option.copyWith(clear: false),
              hasNext: target == _page + 1 ? false : current.hasNext,
              // A window reset already moved the landed page to the first one,
              // so there is nothing before it either.
              hasPrev: target == _page - 1 || _page == 0
                  ? false
                  : current.hasPrev,
            ),
          ),
        );
        return;
      }

      _page = result.index;
      state = FetchResult.data(
        current.copyWith(
          posts: List.unmodifiable(result.posts),
          option: option.copyWith(clear: false),
          pageIndex: result.index + 1,
          hasNext: result.rawCount > 0,
          hasPrev: result.index > 0,
          // A step replaces the displayed posts instead of growing a list, so
          // any ceiling an earlier infinite session hit does not apply here.
          limitReached: false,
        ),
      );
    } catch (err, stack) {
      if (!ref.mounted) return;
      _retryTarget = target;
      state = FetchResult.error(
        windowChanged
            ? _emptyWindow(current.copyWith(option: option))
            : _alignPageLabel(current.copyWith(option: option)),
        error: err,
        stackTrace: stack,
      );
    } finally {
      _fetching = false;
      _drainPending();
      _drainReload();
    }
  }

  /// Fetches the page after the last landed one and appends its displayable
  /// posts, keeping the accumulated list intact.
  ///
  /// The append path only runs in infinite mode. Its failure is retried by
  /// [load] through [_retryAppend], so the posts already on screen are not
  /// replaced by the page that failed to arrive.
  Future<void> _appendNextPage() async {
    if (!_hasServer()) return;

    final server = _server;
    if (_refuseBlockedQuery(server)) return;

    final current = state.data;
    final settings = ref.read(serverSettingStateProvider);
    final option = current.option.copyWith(
      limit: settings.postLimit,
      searchRating: settings.searchRating,
    );
    // The window moved under the loaded posts: their page indexes no longer
    // address the same results, so the list has to restart rather than append
    // a page from another window.
    if (_windowChanged(option, current.option)) {
      _page = 0;
      await load();
      return;
    }

    _fetching = true;
    try {
      state = FetchResult.loading(current.copyWith(option: option));

      final result = await _fetchPage(option, server, _page + 1);
      if (!ref.mounted) return;
      if (result == null || result.posts.isEmpty) {
        // The next page had no entries (or nothing displayable that the scan
        // could reach): the server reached the end of what this feed can show.
        // Keep what is already displayed and stop offering more.
        state = FetchResult.data(
          current.copyWith(
            option: option.copyWith(clear: false),
            hasNext: false,
          ),
        );
        return;
      }

      // Pages can overlap when new posts arrive at the top between requests,
      // so a post is kept once per server-scoped id.
      final seen = {for (final post in current.posts) feedPostKeyOf(post)};
      final merged = [
        ...current.posts,
        ...result.posts.where((post) => seen.add(feedPostKeyOf(post))),
      ];
      final capped = merged.length > maxAccumulatedPosts;
      final posts = capped ? merged.sublist(0, maxAccumulatedPosts) : merged;

      _page = result.index;
      state = FetchResult.data(
        current.copyWith(
          posts: List.unmodifiable(posts),
          option: option.copyWith(clear: false),
          pageIndex: result.index + 1,
          // Only a literal empty page proves the end; the raw answer may carry
          // entries the filters removed.
          hasNext: result.rawCount > 0,
          hasPrev: result.index > 0,
          limitReached: capped,
        ),
      );
    } catch (err, stack) {
      if (!ref.mounted) return;
      _retryAppend = true;
      state = FetchResult.error(
        current.copyWith(option: option),
        error: err,
        stackTrace: stack,
      );
    } finally {
      _fetching = false;
      _drainPending();
      _drainReload();
    }
  }

  /// Applies an option that arrived while a fetch was in flight and reloads
  /// with it.
  void _drainPending() {
    final pending = _pendingOption;
    if (pending == null) return;
    _pendingOption = null;
    // The queued option is the last thing the reader asked for, so it always
    // supersedes a retry aimed at the page that request failed on.
    _retryTarget = null;
    _retryAppend = false;
    if (!ref.mounted) return;
    state = state.copyWith(data: state.data.copyWith(option: pending));
    unawaited(load());
  }

  /// Runs the reload a caller asked for while a fetch was in flight, once that
  /// fetch settled.
  void _drainReload() {
    if (!_reloadPending) return;
    _reloadPending = false;
    if (!ref.mounted) return;
    // A queued option reloads with the settings current at that point, which
    // is the state this reload would read.
    if (_fetching) return;
    unawaited(load());
  }

  /// Fetches [startIndex] (0-based) from [server], skipping pages that yield
  /// no visible posts (up to [_maxSkippedPages]) in [direction].
  ///
  /// Returns `null` when nothing was there to examine: a literal empty
  /// response is terminal and means the end of the results. When entries
  /// existed but every one of them was filtered, the returned record carries
  /// an empty post list instead, so the caller can name the filter rather than
  /// an empty query.
  ///
  /// The posts are filtered by the tags blocker only. Favorite and download
  /// hiding is applied by the feed as it renders, so a post stays in the page
  /// data and comes back the moment its filter is lifted; the hidden set is
  /// read here only to decide whether the page has anything left to show.
  Future<_PageFetch?> _fetchPage(
    PageOption option,
    Server server,
    int startIndex, {
    int direction = 1,
  }) async {
    final repo = ref.read(imageboardRepoProvider(server));
    // One server, one request, one blocker set: both are resolved before the
    // first await, so a session that loses its server mid-loop cannot answer
    // with posts the blockers of the server that was actually asked exclude.
    final blocked = _blockedExpressionsFor(server);
    // Local filters are treated like blocked tags for the skip: a page whose
    // every entry is hidden is skipped, so turning the filter on cannot leave
    // the reader on an empty grid while the server still has more results.
    final hidden = ref.read(hiddenFeedPostKeysProvider);
    var index = startIndex;
    var skips = 0;
    var sawEntries = false;

    while (true) {
      final res = await repo.getPage(option, index);
      // A literal empty response is terminal: the server has no more entries.
      if (res.rawCount == 0) {
        if (!sawEntries) return null;
        return (index: index, posts: const <Post>[], rawCount: 0);
      }
      sawEntries = true;

      final posts = res
          .where((it) => !matchesBlockedTagExpressions(blocked, it.allTags))
          .toList();
      final visible = hidden.isEmpty
          ? posts
          : posts.where((it) => !hidden.contains(feedPostKeyOf(it)));
      if (visible.isNotEmpty) {
        return (index: index, posts: posts, rawCount: res.rawCount);
      }

      // The page had entries but none of them are displayable; try the next
      // one.
      if (skips >= _maxSkippedPages) {
        return (index: index, posts: const <Post>[], rawCount: res.rawCount);
      }
      skips++;
      index += direction;
      if (index < 0) return null;
    }
  }
}
