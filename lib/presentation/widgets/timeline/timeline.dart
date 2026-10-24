import 'dart:async';
import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/pigeon/storage_util.pi.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/post_selection_provider.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/gesture_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/screens/post/enhanced_post_viewer.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/entity/content.dart';
import 'package:boorusphere/presentation/utils/extensions/booru_rating.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/download_dialog.dart';
import 'package:boorusphere/presentation/widgets/timeline/post_context_menu.dart';
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
import 'package:url_launcher/url_launcher_string.dart';

/// Selection border width for multi-select mode on timeline thumbnails.
const double _kSelectionBorderWidth = 3.0;

/// Neutral scrim used by the on-image overlays. Image content is arbitrary, so
/// these can't come from the [ColorScheme]; the fixed black gradient is one of
/// two documented exceptions to the adaptive-palette rule.
const Color _kScrimStrong = Color(0x8A000000); // ~54% black
const Color _kScrimClear = Color(0x00000000);
const Color _kLabelBackground = Color(0xB3000000); // ~70% black

/// Tag category accents for the on-image chip, following the booru convention
/// (artist orange, copyright purple, character green, general blue). The chip
/// is drawn straight on an arbitrary image, so these are fixed hues rather than
/// scheme tokens — the other documented exception to the adaptive-palette rule.
const Color _kTagArtist = Color(0xFFFFB74D);
const Color _kTagCopyright = Color(0xFFBA68C8);
const Color _kTagCharacter = Color(0xFF81C784);
const Color _kTagGeneral = Color(0xFF64B5F6);

/// Opacity of the tag pill's category tint and its matching hairline border,
/// so the pill reads as a soft capsule without hiding the image behind it.
const double _kTagPillFill = 0.20;
const double _kTagPillBorder = 0.45;

/// Tile width at which the on-image overlays render at full size, and the floor
/// they shrink to however dense the grid gets.
const double _kOverlayBaseWidth = 130;
const double _kOverlayMinScale = 0.7;

/// Scale for the on-image overlay type and icons, derived from the tile width
/// so a dense grid shrinks the labels instead of clipping them away.
double _overlayScale(double tileWidth) =>
    (tileWidth / _kOverlayBaseWidth).clamp(_kOverlayMinScale, 1.0).toDouble();

/// The theme's small label style resized for the current overlay [scale], so
/// every on-image label shrinks by the same amount.
TextStyle _overlayLabelStyle(BuildContext context, double scale) {
  final base = context.theme.textTheme.labelSmall ?? const TextStyle();
  return base.copyWith(fontSize: (base.fontSize ?? 11) * scale);
}

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

/// First safe http(s) target for the "open source" action: the post's own
/// source page, then the booru post page, then the raw file.
String? _sourceLinkOf(Post post) {
  if (isSafeUrl(post.source)) return post.source;
  if (isSafeUrl(post.postUrl)) return post.postUrl;
  if (isSafeUrl(post.originalFile)) return post.originalFile;
  return null;
}

/// The most identifying tag for the card chip — artist first, then the
/// copyright (manga/anime/game), character and finally general tag — paired
/// with the category accent that tints it.
({String label, Color color})? _topTagOf(Post post) {
  if (post.tagsArtist.isNotEmpty) {
    return (label: post.tagsArtist.first, color: _kTagArtist);
  }
  if (post.tagsCopyright.isNotEmpty) {
    return (label: post.tagsCopyright.first, color: _kTagCopyright);
  }
  if (post.tagsCharacter.isNotEmpty) {
    return (label: post.tagsCharacter.first, color: _kTagCharacter);
  }
  if (post.tagsGeneral.isNotEmpty) {
    return (label: post.tagsGeneral.first, color: _kTagGeneral);
  }
  return null;
}

/// Accessible name for a timeline card: the identifying tag, the rating and
/// the score. Everything the card draws on the image is folded in here, so the
/// card reads as one item instead of a set of loose chips.
String _cardSemanticsLabel(BuildContext context, Post post) {
  final tag = _topTagOf(post);
  final rating = post.rating.describe(context);

  final ext = post.originalFile.fileExt.toUpperCase();
  final dimensions = post.width > 0 && post.height > 0
      ? '${post.width}×${post.height}'
      : '';

  // Everything the card draws is folded in here, so the overlays can stay out
  // of the semantics tree. A post with no tag, rating or score still needs a
  // name, hence the id fallback.
  final parts = [
    if (tag != null) tag.label,
    if (rating.isNotEmpty) rating,
    if (post.score != 0) '${context.t.score} ${post.score}',
    if (ext.isNotEmpty) ext,
    if (dimensions.isNotEmpty) dimensions,
  ];

  return parts.isEmpty ? '#${post.id}' : parts.join(', ');
}

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
    final cacheBaseWidth = (screenWidth * dpr / flexibleGrid).round();

    // The base constructor is used instead of `SliverMasonryGrid.count` so
    // the child delegate can turn off the automatic keep-alive and repaint
    // boundary wrappers: the masonry render object ignores keep-alives and
    // every item is already wrapped in a RepaintBoundary below, so the
    // wrappers are pure overhead. (`count` in flutter_staggered_grid_view
    // 0.7.0 exposes neither flag.)
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // The overlays are sized from the width the grid actually hands each
        // tile, so a dense grid shrinks them instead of clipping the labels.
        final tileWidth =
            (constraints.crossAxisExtent -
                DesignTokens.spacingSm * (flexibleGrid - 1)) /
            flexibleGrid;
        final overlayScale = _overlayScale(tileWidth);

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
                  overlayScale: overlayScale,
                  cacheBaseWidth: cacheBaseWidth,
                  postdata: (index, postsList[index]),
                  controller: scrollController,
                  blurExplicit: blurExplicit,
                  enableSelection: enableSelection,
                  onTap: () {
                    context.scaffoldMessenger.removeCurrentSnackBar();

                    // Use enhanced post viewer with configurable swipe mode
                    final gestureSettings = ref.read(
                      gestureSettingStateProvider,
                    );
                    EnhancedPostViewer.open(
                      context,
                      index: index,
                      posts: postsList,
                      swipeMode: gestureSettings.swipeMode,
                      swipeThreshold: gestureSettings.swipeDownThreshold,
                      enableSwipeToDetails:
                          gestureSettings.enableSwipeToDetails,
                      enableSwipeToDismiss:
                          gestureSettings.enableSwipeToDismiss,
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
      },
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
    required this.overlayScale,
    required this.cacheBaseWidth,
  });

  final (int, Post) postdata;
  final AutoScrollController controller;
  final bool blurExplicit;
  final bool enableSelection;
  final void Function()? onTap;
  final int gridSize;
  final double overlayScale;
  final int cacheBaseWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (index, post) = postdata;
    final isSelected = ref.watch(
      postSelectionProvider.select((sel) => sel.contains(post.id)),
    );

    void handleTap() {
      if (enableSelection && ref.read(postSelectionProvider).isNotEmpty) {
        // If selection mode is active, toggle selection
        ref.read(postSelectionProvider.notifier).toggle(post.id);
      } else if (onTap != null) {
        // Otherwise, open the post viewer
        onTap!();
      }
    }

    void handleLongPress() {
      HapticFeedback.mediumImpact();
      unawaited(_showCardMenu(context, ref));
    }

    return AutoScrollTag(
      key: ValueKey(post.viewId),
      controller: controller,
      index: index,
      highlightColor: context.theme.colorScheme.surfaceTint,
      // One node per card. The visible overlays are excluded from the
      // semantics tree (their text is folded into the label below), so a
      // screen reader announces the post and its state once instead of
      // reading a handful of unlabelled chips.
      child: Semantics(
        container: true,
        button: true,
        selected: enableSelection ? isSelected : null,
        label: _cardSemanticsLabel(context, post),
        onTap: handleTap,
        onLongPress: handleLongPress,
        child: ExcludeSemantics(
          child: GestureDetector(
            // Opaque so taps anywhere on the card (including the overlay
            // labels) open the viewer like taps on the thumbnail do.
            behavior: HitTestBehavior.opaque,
            onTap: handleTap,
            onLongPress: handleLongPress,
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
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 44 * overlayScale,
                    child: const IgnorePointer(child: _OverlayScrim(top: true)),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 64 * overlayScale,
                    child: const IgnorePointer(
                      child: _OverlayScrim(top: false),
                    ),
                  ),
                  // Top-left: score + rating badge. Replaced by the selection
                  // checkbox while the card is selected.
                  if (!isSelected)
                    Positioned(
                      top: DesignTokens.spacingXs,
                      left: DesignTokens.spacingXs,
                      right: DesignTokens.spacingXs,
                      child: IgnorePointer(
                        child: _ScoreRatingOverlay(
                          post: post,
                          scale: overlayScale,
                        ),
                      ),
                    ),
                  // Top-right: media file type (PNG / JPG / GIF / MP4 / WEBP).
                  Positioned(
                    top: DesignTokens.spacingXs,
                    right: DesignTokens.spacingXs,
                    child: IgnorePointer(
                      child: _MediaTypeLabel(post: post, scale: overlayScale),
                    ),
                  ),
                  // Bottom: tag chip pinned left, dimensions pinned right.
                  Positioned(
                    left: DesignTokens.spacingXs,
                    right: DesignTokens.spacingXs,
                    bottom: DesignTokens.spacingXs,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: _TagChip(post: post, scale: overlayScale),
                          ),
                        ),
                        const SizedBox(width: DesignTokens.spacingSm),
                        Flexible(
                          child: _DimensionsLabel(
                            post: post,
                            scale: overlayScale,
                          ),
                        ),
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
        ),
      ),
    );
  }

  /// Opens the card's quick-action menu (select, favorite, download, share,
  /// open source) as a floating glass card over the timeline.
  Future<void> _showCardMenu(BuildContext context, WidgetRef ref) async {
    final (_, post) = postdata;
    final isSelected = ref.read(postSelectionProvider).contains(post.id);
    final isFavorite = ref.read(favoritePostStateProvider).contains(post);
    final shareLink = post.postUrl.isNotEmpty
        ? post.postUrl
        : post.originalFile;
    final sourceLink = _sourceLinkOf(post);
    final canShare = isSafeUrl(shareLink);

    final action = await showPostContextMenu(
      context,
      groups: [
        [
          if (enableSelection)
            PostContextMenuEntry(
              action: PostContextMenuAction.select,
              icon: isSelected
                  ? Icons.check_circle
                  : Icons.check_circle_outline,
              label: isSelected
                  ? context.t.postAction.deselect
                  : context.t.postAction.select,
            ),
          PostContextMenuEntry(
            action: PostContextMenuAction.favorite,
            icon: isFavorite ? Icons.favorite : Icons.favorite_border,
            label: isFavorite
                ? context.t.postAction.unfavorite
                : context.t.postAction.favorite,
          ),
        ],
        [
          PostContextMenuEntry(
            action: PostContextMenuAction.download,
            icon: Icons.download_outlined,
            label: context.t.postAction.download,
          ),
          PostContextMenuEntry(
            action: PostContextMenuAction.share,
            icon: Icons.share_outlined,
            label: context.t.postAction.share,
            enabled: canShare,
          ),
        ],
        [
          PostContextMenuEntry(
            action: PostContextMenuAction.source,
            icon: Icons.link_outlined,
            label: context.t.postAction.openSource,
            enabled: sourceLink != null,
          ),
        ],
      ],
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case PostContextMenuAction.select:
        ref.read(postSelectionProvider.notifier).toggle(post.id);
      case PostContextMenuAction.favorite:
        final favorites = ref.read(favoritePostStateProvider.notifier);
        if (isFavorite) {
          unawaited(favorites.remove(post));
        } else {
          unawaited(favorites.save(post));
        }
      case PostContextMenuAction.download:
        final started = await DownloaderDialog.show(context, ref, post);
        // A dismissed picker reports null: nothing was asked for, so nothing
        // failed.
        if (started == false && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.downloads.failedToStart)),
          );
        }
      case PostContextMenuAction.share:
        unawaited(StorageUtil().shareText(shareLink, null));
      case PostContextMenuAction.source:
        if (sourceLink != null) {
          unawaited(
            launchUrlString(sourceLink, mode: LaunchMode.externalApplication),
          );
        }
    }
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
  const _ScoreRatingOverlay({required this.post, required this.scale});

  final Post post;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final badge = ratingBadgeOf(post.rating, context.colorScheme);
    if (badge == null && post.score == 0) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (post.score != 0) ...[
          Icon(Icons.star_rounded, size: 13 * scale, color: Colors.white),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              _compactCount(post.score),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: _overlayLabelStyle(
                context,
                scale,
              ).copyWith(color: Colors.white, fontWeight: FontWeight.w600),
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
            scale: scale,
          ),
      ],
    );
  }
}

/// Top-right overlay: the media file type (`PNG`, `JPG`, `GIF`, `MP4`, ...),
/// derived from the original file extension. Hidden when unknown.
class _MediaTypeLabel extends StatelessWidget {
  const _MediaTypeLabel({required this.post, required this.scale});

  final Post post;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final ext = post.originalFile.fileExt.toUpperCase();
    if (ext.isEmpty) return const SizedBox.shrink();

    final isVideo = post.originalFile.asContent().isVideo;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3 * scale),
      decoration: const BoxDecoration(
        color: _kLabelBackground,
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusSm)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isVideo) ...[
            Icon(Icons.play_arrow, size: 12 * scale, color: Colors.white),
            const SizedBox(width: 2),
          ],
          Text(
            ext,
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: _overlayLabelStyle(context, scale).copyWith(
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

/// Bottom-left overlay: the most identifying tag name (e.g. `niten`) in a
/// translucent pill tinted by its category, so the image stays visible behind
/// it. Hidden when the post has no tags.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.post, required this.scale});

  final Post post;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tag = _topTagOf(post);
    if (tag == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingSm * scale,
        vertical: 2 * scale,
      ),
      decoration: BoxDecoration(
        color: tag.color.withValues(alpha: _kTagPillFill),
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        border: Border.all(color: tag.color.withValues(alpha: _kTagPillBorder)),
      ),
      child: Text(
        tag.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: TextScaler.noScaling,
        style: _overlayLabelStyle(context, scale).copyWith(
          color: tag.color,
          fontWeight: FontWeight.w700,
          // Coloured text is weaker than the white labels, so it carries a
          // slightly stronger shadow to stay readable over bright images.
          shadows: const [Shadow(blurRadius: 3, color: Color(0xCC000000))],
        ),
      ),
    );
  }
}

/// Bottom-right overlay: the original dimensions (`3840×2160`). Hidden when
/// the booru didn't report a size.
class _DimensionsLabel extends StatelessWidget {
  const _DimensionsLabel({required this.post, required this.scale});

  final Post post;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (post.width <= 0 || post.height <= 0) return const SizedBox.shrink();

    return Text(
      '${post.width}×${post.height}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      textScaler: TextScaler.noScaling,
      style: _overlayLabelStyle(context, scale).copyWith(
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
    required this.scale,
  });

  final String label;
  final Color color;
  final String semanticLabel;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingXs * scale,
        vertical: scale,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Text(
        label,
        semanticsLabel: semanticLabel,
        maxLines: 1,
        textScaler: TextScaler.noScaling,
        style: _overlayLabelStyle(
          context,
          scale,
        ).copyWith(color: color, fontWeight: FontWeight.w700),
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
    // Tall posts are drawn clamped to 0.5, so the decode follows the rendered
    // box rather than the source ratio — otherwise a 1:10 strip decodes ten
    // times the pixels it can show.
    final renderedRatio = isLong ? 0.5 : post.aspectRatio;
    final cacheHeight = (cacheWidth / renderedRatio).round();

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

/// Moves [color] along its saturation and lightness axes, clamping both to
/// the 0..1 range HSLColor expects.
Color _shiftHsl(Color color, {double saturation = 0, double lightness = 0}) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation((hsl.saturation + saturation).clamp(0.0, 1.0))
      .withLightness((hsl.lightness + lightness).clamp(0.0, 1.0))
      .toColor();
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.isFailed = false});

  final bool isFailed;

  @override
  Widget build(BuildContext context) {
    if (isFailed) {
      return const Material(child: Icon(Icons.broken_image_outlined));
    }

    final surface = context.colorScheme.surface;
    final baseColor = context.isLightThemed
        ? _shiftHsl(surface, saturation: -0.5, lightness: -0.02)
        : surface;
    final highlightColor = context.isLightThemed
        ? _shiftHsl(surface, saturation: -0.5, lightness: 0.02)
        : _shiftHsl(surface, lightness: 0.05);

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
      // A shimmer is looping decorative motion; under reduced motion the
      // placeholder keeps its tint and stops sweeping.
      enabled: !context.reducedMotion,
      child: Container(color: Colors.black, child: const SizedBox.expand()),
    );
  }
}
