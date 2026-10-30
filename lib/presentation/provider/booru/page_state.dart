import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/entity/page_data.dart';
import 'package:boorusphere/presentation/provider/search_history_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/utils/extensions/string.dart';
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

  @override
  FetchResult<PageData> build() {
    _page = 0;
    _fetching = false;
    _pendingOption = null;
    _reloadPending = false;
    _retryTarget = null;
    return const FetchResult.idle(PageData());
  }

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

  Iterable<String> get blockedTags => _blockedTagsFor(_server);

  /// The blockers that apply to [server]: a tag blocked on one booru is still
  /// a usable tag on the others.
  Iterable<String> _blockedTagsFor(Server server) {
    return ref
        .read(tagsBlockerStateProvider)
        .values
        .where((it) => it.serverId.isEmpty || it.serverId == server.id)
        .map((it) => it.name)
        .toSet(); // Convert to Set for O(1) lookup performance
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

  /// Reports a query that contains a tag blocked on [server], and whether it
  /// did.
  ///
  /// The query can be blocked after it was loaded, so every way into a fetch
  /// runs this check: a page of a blocked query is still a page of that query.
  bool _refuseBlockedQuery(Server server) {
    final query = state.data.option.query;
    if (!query.toWordList().any(_blockedTagsFor(server).contains)) return false;
    state = FetchResult.error(state.data, error: BooruError.tagsBlocked);
    return true;
  }

  Future<void> update(PageOption Function(PageOption) updater) async {
    // A change queued during a fetch has not reached [state] yet; building the
    // next one from the committed option would silently drop it.
    final newOption = updater(_pendingOption ?? state.data.option);
    _retryTarget = null;
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

    final query = state.data.option.query;
    _fetching = true;
    try {
      if (query.isNotEmpty) {
        await ref.read(searchHistoryStateProvider.notifier).save(query, server);
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
      if (option.clear || _windowChanged(option, shown)) {
        _page = 0;
      }

      state = FetchResult.loading(state.data.copyWith(option: option));

      var result = await _fetchPage(option, server, _page);
      // The page can be popped while the request is on the wire; the element
      // is gone then and every further write would throw.
      if (!ref.mounted) return;
      if (result == null && _page > 0) {
        // An empty answer for a deep page only proves that page is past the
        // end. The window can have shifted under a stale index, so ask for the
        // first page before telling the reader the query has no results.
        _page = 0;
        result = await _fetchPage(option, server, 0);
        if (!ref.mounted) return;
      }
      if (result == null) {
        // No displayable posts on the first page: keep the existing
        // empty-result error behavior.
        state = FetchResult.error(
          _alignPageLabel(state.data),
          error: BooruError.empty,
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
        ),
      );
    } catch (err, stack) {
      if (!ref.mounted) return;
      state = FetchResult.error(
        _alignPageLabel(state.data),
        error: err,
        stackTrace: stack,
      );
    } finally {
      _fetching = false;
      _drainPending();
      _drainReload();
    }
  }

  /// Loads the next page, replacing the currently displayed posts.
  Future<void> nextPage() async {
    if (!ref.mounted) return;
    if (_fetching) return;
    if (!state.data.hasNext) return;
    if (state.data.posts.isEmpty) return;
    await _navigateTo(_page + 1);
  }

  /// Loads the previous page, replacing the currently displayed posts.
  Future<void> prevPage() async {
    if (!ref.mounted) return;
    if (_fetching) return;
    if (!state.data.hasPrev) return;
    if (_page <= 0) return;
    if (state.data.posts.isEmpty) return;
    await _navigateTo(_page - 1);
  }

  /// Loads [page] (1-based), replacing the currently displayed posts.
  Future<void> goToPage(int page) async {
    if (!ref.mounted) return;
    if (_fetching) return;
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
      if (result == null) {
        // The navigation target has no displayable posts: keep the displayed
        // posts and stay on the current page. Only a failed step to the page
        // right next door proves the end of the results; a jump further ahead
        // says nothing about the neighbour still on offer, and disabling that
        // arrow would strand the reader on this page.
        state = FetchResult.data(
          _alignPageLabel(
            current.copyWith(
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
        ),
      );
    } catch (err, stack) {
      if (!ref.mounted) return;
      _retryTarget = target;
      state = FetchResult.error(
        _alignPageLabel(current.copyWith(option: option)),
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
  /// no displayable posts (up to [_maxSkippedPages]) in [direction].
  ///
  /// Returns `null` when the response is empty (a literal empty response is
  /// terminal — it means the end of the results) or when every skipped page
  /// was fully blocked.
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
    final blocked = _blockedTagsFor(server);
    var index = startIndex;
    var skips = 0;

    while (true) {
      final res = await repo.getPage(option, index);
      // A literal empty response is terminal: the server has no more entries.
      if (res.rawCount == 0) return null;

      final posts = res
          .where((it) => !it.allTags.any(blocked.contains))
          .toList();
      if (posts.isNotEmpty) {
        return (index: index, posts: posts, rawCount: res.rawCount);
      }

      // The page had entries but none of them are displayable; try the next
      // one.
      if (skips >= _maxSkippedPages) return null;
      skips++;
      index += direction;
      if (index < 0) return null;
    }
  }
}
