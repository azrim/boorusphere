import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/search_history_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:boorusphere/presentation/widgets/error_info.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SearchSuggestion extends HookConsumerWidget {
  const SearchSuggestion({
    super.key,
    required this.animator,
    required this.searchBar,
  });

  final AnimationController animator;
  final dynamic searchBar; // SearchBarController

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canBeDragged = useState(false);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      color: context.theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Swipe handle with gesture detection - positioned below status bar
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (details) {
                // Only allow dragging when search is open
                canBeDragged.value = searchBar.isOpen;
              },
              onVerticalDragUpdate: (details) {
                if (!canBeDragged.value) return;

                final delta = details.primaryDelta;
                if (delta == null) return;

                // Only allow downward drag (positive delta)
                if (delta > 0) {
                  // Update animation value based on drag distance
                  animator.value -= delta / (screenHeight * 0.3);
                  animator.value = animator.value.clamp(0.0, 1.0);
                }
              },
              onVerticalDragEnd: (details) async {
                if (!canBeDragged.value) return;

                final velocity = details.velocity.pixelsPerSecond.dy;

                if (velocity > 300 || animator.value < 0.7) {
                  // Close search bar
                  await animator.reverse();
                  searchBar.close();
                } else {
                  // Snap back to open
                  await animator.forward();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 1500),
                  tween: Tween(begin: 0.2, end: 0.6),
                  builder: (context, value, child) {
                    return Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: value),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  },
                ),
              ),
            ),
            const Expanded(
              child: CustomScrollView(
                physics: BouncingScrollPhysics(),
                cacheExtent: 100, // Minimal cache for performance
                slivers: [
                  _SearchHistoryHeader(),
                  _SearchHistory(),
                  _SuggestionHeader(),
                  _Suggestion(),
                  SliverToBoxAdapter(
                    child: SizedBox(height: kBottomNavigationBarHeight + 38),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHistoryHeader extends ConsumerWidget {
  const _SearchHistoryHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchBar = ref.watch(searchBarControllerProvider);
    final history = ref.watch(filterHistoryProvider(searchBar.value));

    // Show header immediately when search is open, even with empty query
    if (!searchBar.isOpen || history.isEmpty) {
      return const SliverToBoxAdapter();
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(searchBar.value.trim().isEmpty
                ? context.t.recently
                : '${context.t.recently}: ${searchBar.value}'),
            TextButton(
              onPressed: ref.read(searchHistoryStateProvider.notifier).clear,
              child: Text(context.t.clear),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHistory extends HookConsumerWidget {
  const _SearchHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchBar = ref.watch(searchBarControllerProvider);

    // Optimize history filtering for better performance
    final history = searchBar.value.trim().isEmpty
        ? ref.watch(searchHistoryStateProvider) // Show all history
        : ref.watch(
            filterHistoryProvider(searchBar.value)); // Show filtered history

    // Don't show history if search bar is closed
    if (!searchBar.isOpen) {
      return const SliverToBoxAdapter();
    }

    // Show empty state if no history
    if (history.entries.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.history,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                searchBar.value.trim().isEmpty
                    ? 'No search history yet'
                    : 'No matching history found',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                searchBar.value.trim().isEmpty
                    ? 'Your recent searches will appear here'
                    : 'Try a different search term',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Convert to list once and limit items for better performance
    final historyList = history.entries.toList();
    final itemCount = (historyList.length).clamp(0, 15);

    return SliverList.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final reversed = historyList.length - 1 - index;
        final entry = historyList[reversed];
        return RepaintBoundary(
          child: Dismissible(
            key: Key(entry.key.toString()),
            direction: DismissDirection.endToStart,
            onDismissed: (direction) {
              ref.read(searchHistoryStateProvider.notifier).delete(entry.key);
            },
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            child: _SuggestionEntryTile(
              data: _SuggestionEntry(
                isHistory: true,
                text: entry.value.query,
                server: entry.value.server,
              ),
              onTap: (str) {
                searchBar.submit(context, str);
              },
              onAdded: searchBar.appendTyped,
            ),
          ),
        );
      },
    );
  }
}

class _SuggestionHeader extends ConsumerWidget {
  const _SuggestionHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final server = ref.watch(serverStateProvider).getById(session.serverId);
    final searchBar = ref.watch(searchBarControllerProvider);

    // Only show suggestion header when user starts typing
    if (!searchBar.isOpen || searchBar.value.trim().length < 2) {
      return const SliverToBoxAdapter();
    }

    if (!server.canSuggestTags) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.search_off, size: 32),
              const SizedBox(height: 8),
              Text(
                context.t.suggestion.notSupported(serverName: server.name),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      sliver: SliverToBoxAdapter(
        child: Text(
          context.t.suggestion.suggested(serverName: server.name),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class _Suggestion extends HookConsumerWidget {
  const _Suggestion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final server = ref.watch(serverStateProvider).getById(session.serverId);
    final searchBar = ref.watch(searchBarControllerProvider);
    final suggestion = ref.watch(suggestionStateProvider);

    // Load suggestions when user starts typing (2+ chars)
    useEffect(() {
      if (searchBar.value.trim().length >= 2) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (searchBar.isOpen && suggestion is! LoadingFetchResult) {
            ref.read(suggestionStateProvider.notifier).get(searchBar.value);
          }
        });
      }
      return null;
    }, [searchBar.value]);

    if (!server.canSuggestTags) {
      return const SliverToBoxAdapter();
    }

    // Show suggestions when user has typed at least 2 characters
    if (searchBar.value.trim().length < 2) {
      return const SliverToBoxAdapter();
    }

    return switch (suggestion) {
      IdleFetchResult() => const SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text('Start typing to see suggestions...'),
            ),
          ),
        ),
      DataFetchResult(:final data) => SliverList.builder(
          itemCount: data.length.clamp(0, 20), // Show more suggestions
          itemBuilder: (context, index) {
            final suggestion = data.elementAt(index);
            return RepaintBoundary(
              child: _SuggestionEntryTile(
                data: _SuggestionEntry(
                  isHistory: false,
                  text: suggestion.name,
                  postCount: suggestion.count,
                ),
                onTap: (str) => searchBar.submit(context, str),
                onAdded: searchBar.appendTyped,
              ),
            );
          },
        ),
      LoadingFetchResult() => const SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      ErrorFetchResult(:final error) => _ErrorSuggestion(
          error: error,
          query: searchBar.value,
          serverName: server.name,
        ),
    };
  }
}

class _ErrorSuggestion extends StatelessWidget {
  const _ErrorSuggestion({
    required this.query,
    required this.serverName,
    required this.error,
  });

  final String query;
  final String serverName;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final err = error;
    Object? msg;

    if (err == BooruError.empty) {
      msg = context.t.suggestion.empty(query: query);
    } else if (err is DioException && err.response?.statusCode != null) {
      msg = context.t.suggestion
          .httpError(query: query, serverName: serverName)
          .withDioExceptionCode(err);
    } else {
      msg = err;
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverToBoxAdapter(
        child: ErrorInfo(error: msg),
      ),
    );
  }
}

class _SuggestionEntry {
  _SuggestionEntry({
    this.text = '',
    this.postCount = 0,
    this.server = '',
    required this.isHistory,
  });

  final String text;
  final int postCount;
  final String server;
  final bool isHistory;
}

class _SuggestionEntryTile extends StatelessWidget {
  const _SuggestionEntryTile({
    required this.data,
    required this.onTap,
    required this.onAdded,
  });

  final _SuggestionEntry data;
  final Function(String entry) onTap;
  final Function(String entry) onAdded;

  @override
  Widget build(BuildContext context) {
    // Much lighter implementation - no ListTile overhead
    return InkWell(
      onTap: () => onTap.call(data.text),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              data.isHistory ? Icons.history : Icons.tag,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.text,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (data.server.isNotEmpty)
                    Text(
                      context.t.suggestion.desc(serverName: data.server),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (data.postCount > 0) ...[
              Text(
                data.postCount.toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: 8),
            ],
            InkWell(
              onTap: () => onAdded.call(data.text),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.add,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
