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

  /// Navigation target whose fetch failed, so the next [load] (the retry
  /// button, a pull-to-refresh) resumes the page the user asked for instead of
  /// reloading the one still on screen.
  int? _retryTarget;

  @override
  FetchResult<PageData> build() {
    _page = 0;
    _fetching = false;
    _pendingOption = null;
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
  bool _hasServer() {
    if (_server != Server.empty) return true;
    state = FetchResult.error(state.data);
    return false;
  }

  Iterable<String> get blockedTags {
    return ref
        .read(tagsBlockerStateProvider)
        .values
        .where((it) => it.serverId.isEmpty || it.serverId == _server.id)
        .map((it) => it.name)
        .toSet(); // Convert to Set for O(1) lookup performance
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
  /// `clear` (a new query) restarts from the first page.
  Future<void> load() async {
    // A caller can hand this over and the page can be gone by the time it
    // runs (a rating picked while the timeline closes).
    if (!ref.mounted) return;
    if (!_hasServer()) return;
    if (_fetching) return;

    final retry = _retryTarget;
    if (retry != null) {
      await _navigateTo(retry);
      return;
    }

    final query = state.data.option.query;
    if (query.toWordList().any(blockedTags.contains)) {
      state = FetchResult.error(state.data, error: BooruError.tagsBlocked);
      return;
    }

    _fetching = true;
    try {
      if (query.isNotEmpty) {
        await ref
            .read(searchHistoryStateProvider.notifier)
            .save(query, _server);
      }

      final settings = ref.read(serverSettingStateProvider);
      final previousLimit = state.data.option.limit;
      final option = state.data.option.copyWith(
        limit: settings.postLimit,
        searchRating: settings.searchRating,
      );

      // A new query and a different page size both restart the result set:
      // keeping the old index would point at a window that has shifted.
      if (option.clear || option.limit != previousLimit) {
        _page = 0;
      }

      state = FetchResult.loading(state.data.copyWith(option: option));

      final result = await _fetchPage(option, _page);
      // The page can be popped while the request is on the wire; the element
      // is gone then and every further write would throw.
      if (!ref.mounted) return;
      if (result == null) {
        // No displayable posts on the first page: keep the existing
        // empty-result error behavior.
        state = FetchResult.error(state.data, error: BooruError.empty);
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
      state = FetchResult.error(state.data, error: err, stackTrace: stack);
    } finally {
      _fetching = false;
      _drainPending();
    }
  }

  /// Loads the next page, replacing the currently displayed posts.
  Future<void> nextPage() async {
    if (_fetching) return;
    if (!state.data.hasNext) return;
    if (state.data.posts.isEmpty) return;
    await _navigateTo(_page + 1);
  }

  /// Loads the previous page, replacing the currently displayed posts.
  Future<void> prevPage() async {
    if (_fetching) return;
    if (!state.data.hasPrev) return;
    if (_page <= 0) return;
    if (state.data.posts.isEmpty) return;
    await _navigateTo(_page - 1);
  }

  /// Loads [page] (1-based), replacing the currently displayed posts.
  Future<void> goToPage(int page) async {
    if (_fetching) return;
    if (state.data.posts.isEmpty) return;
    final target = page - 1;
    if (target < 0 || target == _page) return;
    await _navigateTo(target);
  }

  Future<void> _navigateTo(int target) async {
    if (!_hasServer()) return;
    _retryTarget = null;

    final current = state.data;
    final settings = ref.read(serverSettingStateProvider);
    final option = current.option.copyWith(
      limit: settings.postLimit,
      searchRating: settings.searchRating,
    );
    // The result window changed while this page was on screen (a different
    // page size or rating), so the index no longer maps to the same posts;
    // reload from the first page instead of showing a shifted window.
    final windowChanged =
        option.limit != current.option.limit ||
        option.searchRating != current.option.searchRating;
    if (windowChanged) target = 0;
    final direction = windowChanged || target >= _page ? 1 : -1;

    _fetching = true;
    try {
      // Keep the currently displayed posts visible while the fetch is in
      // flight so the grid doesn't flash empty.
      state = FetchResult.loading(current.copyWith(option: option));

      final result = await _fetchPage(option, target, direction: direction);
      if (!ref.mounted) return;
      if (result == null) {
        // The navigation target has no displayable posts: keep the displayed
        // posts and stay on the current page. Only a failed step to the page
        // right next door proves the end of the results; a jump further ahead
        // says nothing about the neighbour still on offer, and disabling that
        // arrow would strand the reader on this page.
        state = FetchResult.data(
          current.copyWith(
            hasNext: target == _page + 1 ? false : current.hasNext,
            hasPrev: target == _page - 1 ? false : current.hasPrev,
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
        current.copyWith(option: option),
        error: err,
        stackTrace: stack,
      );
    } finally {
      _fetching = false;
      _drainPending();
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

  /// Fetches [startIndex] (0-based), skipping pages that yield no displayable
  /// posts (up to [_maxSkippedPages]) in [direction].
  ///
  /// Returns `null` when the response is empty (a literal empty response is
  /// terminal — it means the end of the results) or when every skipped page
  /// was fully blocked.
  Future<_PageFetch?> _fetchPage(
    PageOption option,
    int startIndex, {
    int direction = 1,
  }) async {
    final repo = ref.read(imageboardRepoProvider(_server));
    var index = startIndex;
    var skips = 0;

    while (true) {
      final res = await repo.getPage(option, index);
      // A literal empty response is terminal: the server has no more entries.
      if (res.rawCount == 0) return null;

      // One blocked set per fetch: reading the getter inside the predicate
      // rebuilt it for every post on the page.
      final blocked = blockedTags;
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
