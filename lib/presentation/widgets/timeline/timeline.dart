import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/screens/post/post_viewer.dart';
import 'package:boorusphere/presentation/utils/entity/content.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/images.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tinycolor2/tinycolor2.dart';

class Timeline extends ConsumerWidget {
  const Timeline({super.key, required this.posts});

  final Iterable<Post> posts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = ref.watch(uiSettingStateProvider.select((ui) => ui.grid));
    final screenWidth = context.mediaQuery.size.width;
    final flexibleGrid = (screenWidth / 200).round() + grid;
    final scrollController = ref
        .watch(timelineControllerProvider.select((it) => it.scrollController));
    final blurExplicit =
        ref.watch(contentSettingStateProvider.select((it) => it.blurExplicit));

    // Convert to list once for better performance
    final postsList =
        posts is List<Post> ? posts as List<Post> : posts.toList();

    return SliverMasonryGrid.count(
      crossAxisCount: flexibleGrid,
      key: ObjectKey(flexibleGrid),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childCount: postsList.length,
      itemBuilder: (context, index) {
        return RepaintBoundary(
          child: _ThumbnailCard(
            gridSize: flexibleGrid,
            postdata: (index, postsList[index]),
            controller: scrollController,
            blurExplicit: blurExplicit,
            onTap: () {
              context.scaffoldMessenger.removeCurrentSnackBar();
              PostViewer.open(context, index: index, posts: postsList);
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
  });

  final (int, Post) postdata;
  final AutoScrollController controller;
  final bool blurExplicit;
  final void Function()? onTap;
  final int gridSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (index, post) = postdata;

    return AutoScrollTag(
      key: ValueKey(post.viewId),
      controller: controller,
      index: index,
      highlightColor: context.theme.colorScheme.surfaceTint,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(5)),
        clipBehavior: Clip.hardEdge,
        child: GestureDetector(
          onTap: onTap,
          child: Hero(
            tag: post.viewId,
            flightShuttleBuilder: (flightContext, animation, flightDirection,
                fromHeroContext, toHeroContext) {
              final Hero toHero = toHeroContext.widget as Hero;
              final isLong = post.aspectRatio < 0.5;
              final isPop = flightDirection == HeroFlightDirection.pop;

              return Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: isPop && isLong ? 0.5 : post.aspectRatio,
                    // clip incoming child to avoid overflow that might be
                    // caused by blurExplicit enabled
                    child: isPop ? ClipRect(child: toHero.child) : toHero.child,
                  ),
                ],
              );
            },
            child: _ThumbnailImage(
                post: post, blurExplicit: blurExplicit, gridSize: gridSize),
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
  });

  final Post post;
  final bool blurExplicit;
  final int gridSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(postHeadersFactoryProvider(post));
    // limit timeline thumbnail to 18:9
    final isLong = post.aspectRatio < 0.5;
    final screen =
        context.mediaQuery.size * context.mediaQuery.devicePixelRatio;
    final cacheWidth = (screen.width / (gridSize * 1.3)).round();
    final cacheHeight = (cacheWidth / post.aspectRatio).round();

    // Pre-calculate blur filter to avoid recreating it
    final blurFilter = blurExplicit && post.rating.isExplicit
        ? ImageFilter.blur(sigmaX: 5, sigmaY: 5, tileMode: TileMode.decal)
        : null;

    final image = AspectRatio(
      aspectRatio: isLong ? 0.5 : post.aspectRatio,
      child: ExtendedImage.network(
        // load sample photo when it's above 35:9
        post.aspectRatio < 0.26 && post.sampleFile.asContent().isPhoto
            ? post.sampleFile
            : post.previewFile,
        headers: headers,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        enableLoadState: false,
        // Use pre-calculated filter
        beforePaintImage: blurFilter != null
            ? (canvas, rect, image, paint) {
                paint.imageFilter = blurFilter;
                return false;
              }
            : null,
        loadStateChanged: (state) {
          if (state.wasSynchronouslyLoaded && state.isCompleted) {
            return state.completedWidget;
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: state.isCompleted
                ? state.completedWidget
                : _Placeholder(isFailed: state.isFailed),
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.center,
                fit: StackFit.passthrough,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
          );
        },
      ),
    );

    final content = post.originalFile.asContent();

    return Stack(
      alignment: Alignment.center,
      children: [
        isLong
            ? Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  image,
                  const _LongThumbnailIndicator(),
                ],
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
    return Card(
      color: context.colorScheme.surface.withValues(alpha: 0.8),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(22, 6, 22, 4),
        child: Icon(Icons.gradient, size: 16),
      ),
    );
  }
}

class _MediaTypeIndicator extends StatelessWidget {
  const _MediaTypeIndicator({
    required this.isVideo,
    required this.isGif,
  });

  final bool isVideo;
  final bool isGif;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: isVideo
          ? const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 16,
            )
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
  const _Placeholder({
    this.isFailed = false,
  });

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
          baseColor
        ],
        stops: const <double>[0.0, 0.35, 0.5, 0.65, 1.0],
      ),
      period: const Duration(milliseconds: 700),
      child: Container(
        color: Colors.black,
        child: const SizedBox.expand(),
      ),
    );
  }
}
