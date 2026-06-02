import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/post_selection_provider.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/gesture_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/screens/post/enhanced_post_viewer.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/entity/content.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tinycolor2/tinycolor2.dart';

/// Selection border width for multi-select mode on timeline thumbnails.
const double _kSelectionBorderWidth = 3.0;

/// Reused as the explicit-content blur on thumbnails. Hoisted out of the
/// per-item builder so we don't allocate one [ImageFilter] per visible
/// thumbnail per build.
final ImageFilter _kExplicitBlur = ImageFilter.blur(
  sigmaX: 5,
  sigmaY: 5,
  tileMode: TileMode.decal,
);

/// Hoisted out of the per-thumbnail [Hero] so all visible thumbnails share
/// a single function reference; the previous closure captured `post` and
/// allocated one builder object per visible item per build. The aspect
/// ratio is read off the source [_ThumbnailImage] at flight time.
Widget _thumbnailHeroShuttleBuilder(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final toHero = toHeroContext.widget as Hero;
  final fromHero = fromHeroContext.widget as Hero;
  final fromChild = fromHero.child;
  final aspectRatio = fromChild is _ThumbnailImage
      ? fromChild.post.aspectRatio
      : 1.0;
  final isLong = aspectRatio < 0.5;
  final isPop = flightDirection == HeroFlightDirection.pop;

  return Stack(
    alignment: Alignment.center,
    children: [
      AspectRatio(
        aspectRatio: isPop && isLong ? 0.5 : aspectRatio,
        child: isPop ? ClipRect(child: toHero.child) : toHero.child,
      ),
    ],
  );
}

class Timeline extends ConsumerWidget {
  const Timeline({super.key, required this.posts});

  final Iterable<Post> posts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = ref.watch(uiSettingStateProvider.select((ui) => ui.grid));
    // Aspect-scoped subscriptions: invalidate this build only on changes to
    // size or DPR, not on keyboard insets, brightness, etc.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final flexibleGrid = (screenWidth / 200).round() + grid;
    final scrollController = ref.watch(
      timelineControllerProvider.select((it) => it.scrollController),
    );
    final blurExplicit = ref.watch(
      contentSettingStateProvider.select((it) => it.blurExplicit),
    );

    // Convert to list once for better performance
    final postsList = posts is List<Post>
        ? posts as List<Post>
        : posts.toList();

    // Hoist DPR-scaled width out of the per-item closure so it isn't
    // recomputed for every visible thumbnail. The cache height is
    // post-specific (uses aspect ratio) and stays in `_ThumbnailImage`.
    final cacheBaseWidth = (screenWidth * dpr / (flexibleGrid * 1.3)).round();

    return SliverMasonryGrid.count(
      // No `key: ObjectKey(flexibleGrid)` here — the previous incarnation
      // disposed every thumbnail when the grid count changed (e.g. on
      // rotation), forcing a full re-decode of every visible image.
      crossAxisCount: flexibleGrid,
      mainAxisSpacing: DesignTokens.spacingSm,
      crossAxisSpacing: DesignTokens.spacingSm,
      childCount: postsList.length,
      itemBuilder: (context, index) {
        return RepaintBoundary(
          child: _ThumbnailCard(
            gridSize: flexibleGrid,
            cacheBaseWidth: cacheBaseWidth,
            postdata: (index, postsList[index]),
            controller: scrollController,
            blurExplicit: blurExplicit,
            onTap: () {
              context.scaffoldMessenger.removeCurrentSnackBar();

              // Use enhanced post viewer with configurable swipe mode
              final gestureSettings = ref.read(
                gestureSettingStateNotifierProvider,
              );
              EnhancedPostViewer.open(
                context,
                index: index,
                posts: postsList,
                swipeMode: gestureSettings.swipeMode,
                swipeThreshold: gestureSettings.swipeDownThreshold,
                enableSwipeToDetails: gestureSettings.enableSwipeToDetails,
                enableSwipeToDismiss: gestureSettings.enableSwipeToDismiss,
              );
            },
          ),
        );
      },
    );
  }
}

class _ThumbnailCard extends HookConsumerWidget {
  const _ThumbnailCard({
    required this.postdata,
    required this.controller,
    required this.blurExplicit,
    this.onTap,
    required this.gridSize,
    required this.cacheBaseWidth,
  });

  final (int, Post) postdata;
  final AutoScrollController controller;
  final bool blurExplicit;
  final void Function()? onTap;
  final int gridSize;
  final int cacheBaseWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (index, post) = postdata;
    final selection = ref.watch(postSelectionProvider);
    final isSelected = selection.contains(post.id);

    return AutoScrollTag(
      key: ValueKey(post.viewId),
      controller: controller,
      index: index,
      highlightColor: context.theme.colorScheme.surfaceTint,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: isSelected
              ? Border.all(
                  color: context.theme.colorScheme.primary,
                  width: _kSelectionBorderWidth,
                )
              : null,
        ),
        clipBehavior: Clip.hardEdge,
        child: GestureDetector(
          onTap: () {
            if (selection.isNotEmpty) {
              // If selection mode is active, toggle selection
              ref.read(postSelectionProvider.notifier).toggle(post.id);
            } else if (onTap != null) {
              // Otherwise, open the post viewer
              onTap!();
            }
          },
          onLongPress: () {
            // Enter selection mode and toggle this post
            ref.read(postSelectionProvider.notifier).toggle(post.id);
          },
          child: Stack(
            children: [
              Hero(
                tag: post.viewId,
                flightShuttleBuilder: _thumbnailHeroShuttleBuilder,
                child: _ThumbnailImage(
                  post: post,
                  blurExplicit: blurExplicit,
                  gridSize: gridSize,
                  cacheBaseWidth: cacheBaseWidth,
                ),
              ),
              // Selection checkbox overlay
              if (isSelected)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(DesignTokens.spacingXs),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailImage extends ConsumerWidget {
  const _ThumbnailImage({
    required this.post,
    this.blurExplicit = false,
    required this.gridSize,
    required this.cacheBaseWidth,
  });

  final Post post;
  final bool blurExplicit;
  final int gridSize;
  final int cacheBaseWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(postHeadersFactoryProvider(post));
    // limit timeline thumbnail to 18:9
    final isLong = post.aspectRatio < 0.5;
    final cacheWidth = cacheBaseWidth;
    final cacheHeight = (cacheWidth / post.aspectRatio).round();

    // Reuse the pre-computed blur filter; allocating a new ImageFilter per
    // paint forced the engine to thrash the rasterizer cache.
    final shouldBlur = blurExplicit && post.rating.isExplicit;

    final url = post.aspectRatio < 0.26 && post.sampleFile.asContent().isPhoto
        ? post.sampleFile
        : post.previewFile;

    final image = AspectRatio(
      aspectRatio: isLong ? 0.5 : post.aspectRatio,
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: headers,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        maxWidthDiskCache: cacheWidth,
        maxHeightDiskCache: cacheHeight,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, _) => const _Placeholder(),
        errorWidget: (context, _, __) => const _Placeholder(isFailed: true),
        imageBuilder: shouldBlur
            ? (context, provider) => ImageFiltered(
                imageFilter: _kExplicitBlur,
                child: Image(
                  image: provider,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              )
            : null,
      ),
    );

    final content = post.originalFile.asContent();

    return Stack(
      alignment: Alignment.center,
      children: [
        isLong
            ? Stack(
                alignment: Alignment.bottomCenter,
                children: [image, const _LongThumbnailIndicator()],
              )
            : image,
        // Add overlay icons for GIF and video
        if (content.isGif || content.isVideo)
          Positioned(
            top: 8,
            right: 8,
            child: _MediaTypeIndicator(
              isVideo: content.isVideo,
              isGif: content.isGif,
            ),
          ),
      ],
    );
  }
}

class _LongThumbnailIndicator extends StatelessWidget {
  const _LongThumbnailIndicator();

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: Color(0xCC000000), // Pre-computed color
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(DesignTokens.radiusMd),
          topRight: Radius.circular(DesignTokens.radiusMd),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(DesignTokens.spacingLg, DesignTokens.spacingXs, DesignTokens.spacingLg, DesignTokens.spacingXs),
        child: Icon(Icons.gradient, size: 16),
      ),
    );
  }
}

class _MediaTypeIndicator extends StatelessWidget {
  const _MediaTypeIndicator({required this.isVideo, required this.isGif});

  final bool isVideo;
  final bool isGif;

  static const _decoration = BoxDecoration(
    color: Color(0xB3000000), // Pre-computed 0.7 alpha black
    borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusSm)),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: _decoration,
      child: isVideo
          ? const Icon(Icons.play_arrow, color: Colors.white, size: 16)
          : const Text(
              'GIF',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.isFailed = false});

  final bool isFailed;

  @override
  Widget build(BuildContext context) {
    if (isFailed) {
      return const Material(child: Icon(Icons.broken_image_outlined));
    }

    final baseColor = context.isLightThemed
        ? context.colorScheme.surface.desaturate(50).darken(2)
        : context.colorScheme.surface;
    final highlightColor = context.isLightThemed
        ? context.colorScheme.surface.desaturate(50).lighten(2)
        : context.colorScheme.surface.lighten(5);

    return Shimmer(
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[
          baseColor,
          baseColor,
          highlightColor,
          baseColor,
          baseColor,
        ],
        stops: const <double>[0.0, 0.35, 0.5, 0.65, 1.0],
      ),
      period: DesignTokens.durationSlow,
      child: Container(color: Colors.black, child: const SizedBox.expand()),
    );
  }
}
