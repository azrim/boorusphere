import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/post_selection_provider.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/screens/home/home_status.dart';
import 'package:boorusphere/presentation/screens/home/search/search_screen.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class HomeContent extends HookConsumerWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(pageStateProvider);
    final session = ref.watch(searchSessionProvider);
    final servers = ref.watch(serverStateProvider);

    // Optimize blocked tags lookup with Set for O(1) contains check
    final blockedTagsSet = ref.watch(
      tagsBlockerStateProvider.select(
        (state) => state.values
            .where(
              (it) => it.serverId.isEmpty || it.serverId == session.serverId,
            )
            .map((it) => it.name)
            .toSet(), // Convert to Set for faster lookup
      ),
    );

    // Use more efficient filtering with Set lookup
    final filteredPosts = pageState.data.posts
        .where((it) => !it.allTags.any(blockedTagsSet.contains))
        .toList(); // Convert to list once for better performance

    useEffect(() {
      if (servers.isNotEmpty) {
        Future(() {
          ref
              .read(pageStateProvider.notifier)
              .update(
                (option) => option.copyWith(query: session.query, clear: true),
              );
        });
      }
      return null;
    }, [servers.isNotEmpty]);

    final timelineController = ref.watch(timelineControllerProvider);
    final scrollController = timelineController.scrollController;

    // Auto-stretch the scroll past the bottom edge after a fetch settles.
    // The previous implementation enqueued a post-frame callback from inside
    // `build` itself, which fires after every rebuild (every keystroke,
    // every drawer animation tick, etc.). Scoping it to a `useEffect` keyed
    // on `pageState` so it only re-runs when the fetch result actually
    // changes.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients ||
            pageState is DataFetchResult ||
            pageState is LoadingFetchResult) {
          return;
        }

        if (scrollController.position.extentAfter < 300) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.fastOutSlowIn,
          );
        }
      });
      return null;
    }, [pageState, scrollController]);

    final isNewSearch =
        pageState is! DataFetchResult && pageState.data.option.clear;

    // Watch selection state for bottom action bar
    final selection = ref.watch(postSelectionProvider);
    final hasSelection = selection.isNotEmpty;

    return Stack(
      alignment: Alignment.center,
      children: [
        RefreshIndicator(
          onRefresh: () async {
            unawaited(
              ref
                  .read(pageStateProvider.notifier)
                  .update((it) => it.copyWith(clear: true)),
            );
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: scrollController,
            slivers: [
              if (!isNewSearch)
                SliverSafeArea(
                  sliver: SliverPadding(
                    padding: const EdgeInsets.all(10),
                    sliver: Timeline(posts: filteredPosts),
                  ),
                ),
              if (!isNewSearch)
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewPaddingOf(context).bottom * 1.8 + 92,
                  ),
                  sliver: const SliverToBoxAdapter(child: HomeStatus()),
                )
              else
                const SliverFillRemaining(child: HomeStatus()),
            ],
          ),
        ),
        const _EdgeShadow(),
        SearchScreen(scrollController: scrollController),
        // Selection action bar
        if (hasSelection)
          Positioned(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
            left: 16,
            right: 16,
            child: _SelectionActionBar(
              selectedCount: selection.length,
              onDownload: () async {
                // Batch download: download images and create ZIP
                final selectedPosts = filteredPosts
                    .where((post) => selection.contains(post.id))
                    .toList();

                if (selectedPosts.isEmpty) return;

                // Show downloading message
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Downloading ${selectedPosts.length} images...',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }

                try {
                  // Create temp directory for downloads
                  final tempDir = await getTemporaryDirectory();
                  final batchDir = Directory(
                    '${tempDir.path}/batch_download_${DateTime.now().millisecondsSinceEpoch}',
                  );
                  await batchDir.create(recursive: true);

                  // Download each image
                  final dio = Dio();
                  for (int i = 0; i < selectedPosts.length; i++) {
                    final post = selectedPosts[i];
                    // Prefer sample file for smaller size, fallback to original
                    final imageUrl = post.sampleFile.isNotEmpty
                        ? post.sampleFile
                        : post.originalFile;
                    if (imageUrl.isEmpty) continue;

                    // Extract file extension from URL
                    final urlParts = imageUrl.split('.');
                    final ext = urlParts.last.split('?').first;
                    final fileName = '${post.id}.$ext';
                    final filePath = '${batchDir.path}/$fileName';

                    await dio.download(imageUrl, filePath);
                  }

                  // Create ZIP file
                  final archive = Archive();
                  final files = batchDir.listSync();
                  for (final file in files) {
                    if (file is File) {
                      final data = file.readAsBytesSync();
                      final fileName = file.path.split('/').last;
                      archive.addFile(ArchiveFile(fileName, data.length, data));
                    }
                  }

                  // Encode archive to ZIP
                  final zipEncoder = ZipEncoder();
                  final zipData = zipEncoder.encode(archive);
                  if (zipData == null) {
                    throw Exception('Failed to create ZIP archive');
                  }

                  // Save ZIP to documents directory
                  final documentsDir = await getApplicationDocumentsDirectory();
                  final downloadsDir = Directory(
                    '${documentsDir.path}/downloads',
                  );
                  if (!downloadsDir.existsSync()) {
                    downloadsDir.createSync(recursive: true);
                  }

                  final zipFileName =
                      'batch_${DateTime.now().millisecondsSinceEpoch}.zip';
                  final finalZipPath = '${downloadsDir.path}/$zipFileName';
                  final zipFile = File(finalZipPath);
                  await zipFile.writeAsBytes(zipData);

                  // Clean up temp files
                  await batchDir.delete(recursive: true);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Downloaded ${selectedPosts.length} images to $zipFileName',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Batch download failed: $e')),
                    );
                  }
                }
              },
              onFavorite: () async {
                // Batch favorite: add selected posts to favorites
                final selectedPosts = filteredPosts
                    .where((post) => selection.contains(post.id))
                    .toList();
                for (final post in selectedPosts) {
                  await ref.read(favoritePostStateProvider.notifier).save(post);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Added ${selectedPosts.length} posts to favorites',
                      ),
                    ),
                  );
                }
                ref.read(postSelectionProvider.notifier).clear();
              },
              onClear: () {
                ref.read(postSelectionProvider.notifier).clear();
              },
            ),
          ),
      ],
    );
  }
}

class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.selectedCount,
    required this.onDownload,
    required this.onFavorite,
    required this.onClear,
  });

  final int selectedCount;
  final VoidCallback onDownload;
  final VoidCallback onFavorite;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
            TextButton.icon(
              onPressed: onFavorite,
              icon: const Icon(Icons.favorite_border),
              label: const Text('Favorite'),
            ),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear),
              label: Text('$selectedCount'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EdgeShadow extends StatelessWidget {
  const _EdgeShadow();

  @override
  Widget build(BuildContext context) {
    final tint = context.theme.scaffoldBackgroundColor;
    final paddingTop = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: SizedBox(
            height: paddingTop * 1.8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomLeft,
                  colors: [
                    tint.withValues(alpha: 0.8),
                    tint.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
