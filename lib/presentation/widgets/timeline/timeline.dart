import 'dart:async';
import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/pigeon/storage_util.pi.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/post_selection_provider.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/gesture_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/screens/post/enhanced_post_viewer.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/entity/content.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/download_dialog.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/url_validator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tinycolor2/tinycolor2.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Selection border width for multi-select mode on timeline thumbnails.
const double _kSelectionBorderWidth = 3.0;

/// Neutral scrim used by the on-image overlays. Image content is arbitrary, so
/// these can't come from the [ColorScheme]; the fixed black gradient is the
/// documented exception to the adaptive-palette rule.
const Color _kScrimStrong = Color(0x8A000000); // ~54% black
const Color _kScrimClear = Color(0x00000000);
const Color _kLabelBackground = Color(0xB3000000); // ~70% black

/// Compact post score for the on-image badge: `42`, `1.4k`, `12k`, `1.2M`.
String _compactCount(int value) {
  final abs = value.abs();
  if (abs < 1000) return '$value';
  if (abs < 1000000) {
    final scaled = value / 1000;
    return '${scaled.toStringAsFixed(abs < 10000 ? 1 : 0)}k';
  }
  return '${(value / 1000000).toStringAsFixed(1)}M';
}

/// Shared explicit-content blur for thumbnails. A single top-level
/// [ImageFilter] avoids allocating one per visible thumbnail per build.
final ImageFilter _kExplicitBlur = ImageFilter.blur(
  sigmaX: 5,
  sigmaY: 5,
  tileMode: TileMode.decal,
);

/// Hero flight builder shared by every thumbnail, so a single function
/// reference is used instead of one closure per visible item. The aspect
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

/// Rating badge content for the top-left overlay, or `null` for unrated posts
/// (the badge is skipped entirely). Colors come from the active scheme so
/// the badge follows the adaptive palette.
({String label, Color color})? _ratingBadgeOf(
  BooruRating rating,
  ColorScheme scheme,
) {
  return switch (rating) {
    BooruRating.safe => (label: 'S', color: scheme.primary),
    BooruRating.questionable => (label: 'Q', color: scheme.tertiary),
    BooruRating.explicit => (label: 'E', color: scheme.error),
    // "SN" so it can't be mistaken for the safe "S".
    BooruRating.sensitive => (label: 'SN', color: scheme.secondary),
    BooruRating.all => null,
  };
}

/// First safe http(s) target for the "open source" action: the post's own
/// source page, then the booru post page, then the raw file.
String? _sourceLinkOf(Post post) {
  if (isSafeUrl(post.source)) return post.source;
  if (isSafeUrl(post.postUrl)) return post.postUrl;
  if (isSafeUrl(post.originalFile)) return post.originalFile;
  return null;
}

/// The most identifying tag for the card chip: artist first, then the
/// copyright (manga/anime/game), character and finally general tag.
String? _topTagOf(Post post) {
  if (post.tagsArtist.isNotEmpty) return post.tagsArtist.first;
  if (post.tagsCopyright.isNotEmpty) return post.tagsCopyright.first;
  if (post.tagsCharacter.isNotEmpty) return post.tagsCharacter.first;
  if (post.tagsGeneral.isNotEmpty) return post.tagsGeneral.first;
  return null;
}

/// Actions offered by the long-press context menu on a timeline card.
enum _CardMenuAction { select, favorite, download, share, source }

class Timeline extends ConsumerWidget {
  const Timeline({super.key, required this.posts, this.enableSelection = true});

  final Iterable<Post> posts;

  /// Whether cards can enter multi-select mode. Disabled on screens without a
  /// batch action bar (e.g. Favorites), where selecting would be a dead end.
  final bool enableSelection;

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

    // The base constructor is used instead of `SliverMasonryGrid.count` so
    // the child delegate can turn off the automatic keep-alive and repaint
    // boundary wrappers: the masonry render object ignores keep-alives and
    // every item is already wrapped in a RepaintBoundary below, so the
    // wrappers are pure overhead. (`count` in flutter_staggered_grid_view
    // 0.7.0 exposes neither flag.)
    return SliverMasonryGrid(
      // No `key: ObjectKey(flexibleGrid)` here — the previous incarnation
      // disposed every thumbnail when the grid count changed (e.g. on
      // rotation), forcing a full re-decode of every visible image.
      gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: flexibleGrid,
      ),
      mainAxisSpacing: DesignTokens.spacingSm,
      crossAxisSpacing: DesignTokens.spacingSm,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return RepaintBoundary(
            child: _ThumbnailCard(
              gridSize: flexibleGrid,
              cacheBaseWidth: cacheBaseWidth,
              postdata: (index, postsList[index]),
              controller: scrollController,
              blurExplicit: blurExplicit,
              enableSelection: enableSelection,
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
        childCount: postsList.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
      ),
    );
  }
}

class _ThumbnailCard extends HookConsumerWidget {
  const _ThumbnailCard({
    required this.postdata,
    required this.controller,
    required this.blurExplicit,
    required this.enableSelection,
    this.onTap,
    required this.gridSize,
    required this.cacheBaseWidth,
  });

  final (int, Post) postdata;
  final AutoScrollController controller;
  final bool blurExplicit;
  final bool enableSelection;
  final void Function()? onTap;
  final int gridSize;
  final int cacheBaseWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (index, post) = postdata;
    final isSelected = ref.watch(
      postSelectionProvider.select((sel) => sel.contains(post.id)),
    );

    return AutoScrollTag(
      key: ValueKey(post.viewId),
      controller: controller,
      index: index,
      highlightColor: context.theme.colorScheme.surfaceTint,
      child: GestureDetector(
        // Opaque so taps anywhere on the card (including the overlay labels)
        // open the viewer like taps on the thumbnail do.
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (enableSelection && ref.read(postSelectionProvider).isNotEmpty) {
            // If selection mode is active, toggle selection
            ref.read(postSelectionProvider.notifier).toggle(post.id);
          } else if (onTap != null) {
            // Otherwise, open the post viewer
            onTap!();
          }
        },
        // Long-press opens the quick-action menu (select, favorite, download,
        // share, open source).
        onLongPressStart: (details) {
          HapticFeedback.mediumImpact();
          unawaited(_showCardMenu(context, ref, details.globalPosition));
        },
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
              // Neutral gradients keep the overlay labels legible on any image.
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 44,
                child: IgnorePointer(child: _OverlayScrim(top: true)),
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 64,
                child: IgnorePointer(child: _OverlayScrim(top: false)),
              ),
              // Top-left: score + rating badge. Replaced by the selection
              // checkbox while the card is selected.
              if (!isSelected)
                Positioned(
                  top: 4,
                  left: 4,
                  child: IgnorePointer(child: _ScoreRatingOverlay(post: post)),
                ),
              // Top-right: media file type (PNG / JPG / GIF / MP4 / WEBP).
              Positioned(
                top: 4,
                right: 4,
                child: IgnorePointer(child: _MediaTypeLabel(post: post)),
              ),
              // Bottom: tag chip pinned left, dimensions pinned right.
              Positioned(
                left: 4,
                right: 4,
                bottom: 4,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: _TagChip(post: post),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spacingSm),
                    _DimensionsLabel(post: post),
                  ],
                ),
              ),
              // Selection checkbox overlay
              if (isSelected)
                Positioned(
                  top: 6,
                  left: 6,
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

  /// Opens the card's quick-action menu anchored at [globalPosition] (the
  /// long-press point).
  Future<void> _showCardMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) async {
    final (_, post) = postdata;
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlayBox.size,
    );

    final isSelected = ref.read(postSelectionProvider).contains(post.id);
    final isFavorite = ref.read(favoritePostStateProvider).contains(post);
    final shareLink = post.postUrl.isNotEmpty
        ? post.postUrl
        : post.originalFile;
    final sourceLink = _sourceLinkOf(post);
    final canShare = isSafeUrl(shareLink);

    final action = await showMenu<_CardMenuAction>(
      context: context,
      position: position,
      items: [
        if (enableSelection)
          PopupMenuItem(
            value: _CardMenuAction.select,
            child: _MenuRow(
              icon: isSelected
                  ? Icons.check_circle
                  : Icons.check_circle_outline,
              label: isSelected
                  ? context.t.postAction.deselect
                  : context.t.postAction.select,
            ),
          ),
        PopupMenuItem(
          value: _CardMenuAction.favorite,
          child: _MenuRow(
            icon: isFavorite ? Icons.favorite : Icons.favorite_border,
            label: isFavorite
                ? context.t.postAction.unfavorite
                : context.t.postAction.favorite,
          ),
        ),
        PopupMenuItem(
          value: _CardMenuAction.download,
          child: _MenuRow(
            icon: Icons.download_outlined,
            label: context.t.postAction.download,
          ),
        ),
        PopupMenuItem(
          value: _CardMenuAction.share,
          enabled: canShare,
          child: _MenuRow(
            icon: Icons.share_outlined,
            label: context.t.postAction.share,
          ),
        ),
        PopupMenuItem(
          value: _CardMenuAction.source,
          enabled: sourceLink != null,
          child: _MenuRow(
            icon: Icons.link_outlined,
            label: context.t.postAction.openSource,
          ),
        ),
      ],
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case _CardMenuAction.select:
        ref.read(postSelectionProvider.notifier).toggle(post.id);
      case _CardMenuAction.favorite:
        final favorites = ref.read(favoritePostStateProvider.notifier);
        if (isFavorite) {
          unawaited(favorites.remove(post));
        } else {
          unawaited(favorites.save(post));
        }
      case _CardMenuAction.download:
        unawaited(DownloaderDialog.show(context, ref, post));
      case _CardMenuAction.share:
        unawaited(StorageUtil().shareText(shareLink, null));
      case _CardMenuAction.source:
        if (sourceLink != null) {
          unawaited(
            launchUrlString(sourceLink, mode: LaunchMode.externalApplication),
          );
        }
    }
  }
}

/// Icon + label row shared by the context-menu entries.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: DesignTokens.spacingSm),
        Text(label),
      ],
    );
  }
}

/// Fades a neutral scrim into the top or bottom edge of a thumbnail so the
/// overlay labels stay readable regardless of the underlying image.
class _OverlayScrim extends StatelessWidget {
  const _OverlayScrim({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: const [_kScrimStrong, _kScrimClear],
        ),
      ),
    );
  }
}

/// Top-left overlay: score (with a star) and the rating badge. Hidden for
/// unrated posts with no score.
class _ScoreRatingOverlay extends StatelessWidget {
  const _ScoreRatingOverlay({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final badge = _ratingBadgeOf(post.rating, context.colorScheme);
    if (badge == null && post.score == 0) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (post.score != 0) ...[
          const Icon(Icons.star_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            _compactCount(post.score),
            style: context.theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (badge != null && post.score != 0)
          const SizedBox(width: DesignTokens.spacingXs),
        if (badge != null)
          _RatingBadge(
            label: badge.label,
            color: badge.color,
            semanticLabel: post.rating.describe(context),
          ),
      ],
    );
  }
}

/// Top-right overlay: the media file type (`PNG`, `JPG`, `GIF`, `MP4`, ...),
/// derived from the original file extension. Hidden when unknown.
class _MediaTypeLabel extends StatelessWidget {
  const _MediaTypeLabel({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final ext = post.originalFile.fileExt.toUpperCase();
    if (ext.isEmpty) return const SizedBox.shrink();

    final isVideo = post.originalFile.asContent().isVideo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const BoxDecoration(
        color: _kLabelBackground,
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusSm)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isVideo) ...[
            const Icon(Icons.play_arrow, size: 12, color: Colors.white),
            const SizedBox(width: 2),
          ],
          Text(
            ext,
            style: context.theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-left overlay: the most identifying tag name (e.g. `niten`). Hidden
/// when the post has no tags. Uses the scheme's accent chip colors.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final tag = _topTagOf(post);
    if (tag == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
      ),
      child: Text(
        tag,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.theme.textTheme.labelSmall?.copyWith(
          color: context.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Bottom-right overlay: the original dimensions (`3840×2160`). Hidden when
/// the booru didn't report a size.
class _DimensionsLabel extends StatelessWidget {
  const _DimensionsLabel({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    if (post.width <= 0 || post.height <= 0) return const SizedBox.shrink();

    return Text(
      '${post.width}×${post.height}',
      style: context.theme.textTheme.labelSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        shadows: const [Shadow(blurRadius: 2, color: Color(0x80000000))],
      ),
    );
  }
}

/// Tiny letter chip for the post rating.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({
    required this.label,
    required this.color,
    required this.semanticLabel,
  });

  final String label;
  final Color color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingXs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Text(
        label,
        semanticsLabel: semanticLabel,
        style: context.theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
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

    // Long thumbnails get a gradient indicator pinned to the bottom edge.
    return isLong
        ? Stack(
            alignment: Alignment.bottomCenter,
            children: [image, const _LongThumbnailIndicator()],
          )
        : image;
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
        padding: EdgeInsets.fromLTRB(
          DesignTokens.spacingLg,
          DesignTokens.spacingXs,
          DesignTokens.spacingLg,
          DesignTokens.spacingXs,
        ),
        child: Icon(Icons.gradient, size: 16),
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
