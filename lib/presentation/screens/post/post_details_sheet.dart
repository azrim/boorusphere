import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/entity/pixel_size.dart';
import 'package:boorusphere/presentation/utils/extensions/images.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/drag_handle.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

const _kMinSheetSize = 0.0;
const _kSnapSheetSize = 0.5;
const _kMaxSheetSize = 0.9;

class PostDetailsSheet extends ConsumerStatefulWidget {
  const PostDetailsSheet({
    super.key,
    required this.postNotifier,
    required this.sheetController,
    required this.session,
  });

  final ValueNotifier<Post> postNotifier;
  final DraggableScrollableController sheetController;
  final SearchSession session;

  @override
  ConsumerState<PostDetailsSheet> createState() => _PostDetailsSheetState();
}

class _PostDetailsSheetState extends ConsumerState<PostDetailsSheet> {
  final Set<String> _selectedTags = {};
  int? _lastPostId;

  @override
  void initState() {
    super.initState();
    _lastPostId = widget.postNotifier.value.id;
    widget.postNotifier.addListener(_onPostChanged);
  }

  @override
  void didUpdateWidget(covariant PostDetailsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.postNotifier, widget.postNotifier)) {
      oldWidget.postNotifier.removeListener(_onPostChanged);
      widget.postNotifier.addListener(_onPostChanged);
      _lastPostId = widget.postNotifier.value.id;
    }
  }

  @override
  void dispose() {
    widget.postNotifier.removeListener(_onPostChanged);
    super.dispose();
  }

  void _onPostChanged() {
    final newId = widget.postNotifier.value.id;
    if (_lastPostId != newId) {
      _lastPostId = newId;
      if (_selectedTags.isNotEmpty && mounted) {
        setState(_selectedTags.clear);
      }
    }
  }

  void _onTagPressed(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedTags.clear);
  }

  @override
  Widget build(BuildContext context) {
    final enableBlur = ref.watch(uiSettingStateProvider.select((s) => s.blur));
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return DraggableScrollableSheet(
      controller: widget.sheetController,
      initialChildSize: _kMinSheetSize,
      minChildSize: _kMinSheetSize,
      maxChildSize: _kMaxSheetSize,
      snapSizes: const [_kMinSheetSize, _kSnapSheetSize, _kMaxSheetSize],
      snap: true,
      snapAnimationDuration: const Duration(milliseconds: 200),
      builder: (context, scrollController) {
        return RepaintBoundary(
          child: ValueListenableBuilder<Post>(
            valueListenable: widget.postNotifier,
            builder: (context, post, child) {
              // `_selectedTags` clearing on post change is handled by the
              // `_onPostChanged` listener attached in initState; doing it
              // from inside this builder via `addPostFrameCallback` would
              // schedule work on every rebuild (e.g. tag toggles), not
              // only on actual post-id transitions.
              final content = Container(
                decoration: BoxDecoration(
                  color: enableBlur
                      ? backgroundColor.withValues(alpha: 0.85)
                      : backgroundColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(DesignTokens.radiusXl),
                  ),
                ),
                child: Stack(
                  children: [
                    CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        // Drag handle
                        const SliverToBoxAdapter(child: DragHandle(margin: EdgeInsets.symmetric(vertical: 12))),
                        // Content
                        SliverToBoxAdapter(
                          child: _SheetContent(
                            key: ValueKey(
                              'content_${post.id}_${post.serverId}',
                            ),
                            post: post,
                            selectedTags: _selectedTags,
                            onTagPressed: _onTagPressed,
                          ),
                        ),
                      ],
                    ),
                    // Fixed bottom action bar
                    if (_selectedTags.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _TagActionBar(
                          selectedTags: _selectedTags,
                          session: widget.session,
                          onClearSelection: _clearSelection,
                        ),
                      ),
                  ],
                ),
              );

              // Only apply blur when enabled
              if (enableBlur) {
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(DesignTokens.radiusXl),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: content,
                  ),
                );
              }

              return ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(DesignTokens.radiusXl),
                ),
                child: content,
              );
            },
          ),
        );
      },
    );
  }
}

class _TagActionBar extends ConsumerWidget {
  const _TagActionBar({
    required this.selectedTags,
    required this.session,
    required this.onClearSelection,
  });

  final Set<String> selectedTags;
  final SearchSession session;
  final VoidCallback onClearSelection;

  void _copyTags(BuildContext context) {
    final tags = selectedTags.join(' ');
    Clipboard.setData(ClipboardData(text: tags));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.copySuccess),
        duration: const Duration(seconds: 1),
      ),
    );
    onClearSelection();
  }

  void _blockTags(BuildContext context, WidgetRef ref) {
    ref
        .read(tagsBlockerStateProvider.notifier)
        .pushAll(tags: selectedTags.toList());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.actionTag.blocked),
        duration: const Duration(seconds: 1),
      ),
    );
    onClearSelection();
  }

  void _searchTags(BuildContext context) {
    final newQuery = selectedTags.join(' ');
    if (newQuery.isEmpty) return;
    context.router.push(HomeRoute(session: session.copyWith(query: newQuery)));
    onClearSelection();
  }

  void _appendTags(BuildContext context) {
    final existingTags = session.query.toWordList();
    final newQuery = {...existingTags, ...selectedTags}.join(' ');
    if (newQuery.isEmpty) return;
    context.router.push(HomeRoute(session: session.copyWith(query: newQuery)));
    onClearSelection();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingSm, vertical: DesignTokens.spacingSm),
          child: Row(
            children: [
              Text(
                '${selectedTags.length} selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: context.t.actionTag.copy,
                onPressed: () => _copyTags(context),
              ),
              IconButton(
                icon: const Icon(Icons.block, size: 20),
                tooltip: context.t.actionTag.block,
                onPressed: () => _blockTags(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                tooltip: context.t.actionTag.append,
                onPressed: () => _appendTags(context),
              ),
              IconButton(
                icon: const Icon(Icons.search, size: 20),
                tooltip: context.t.actionTag.search,
                onPressed: () => _searchTags(context),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: context.t.clear,
                onPressed: onClearSelection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetContent extends ConsumerWidget {
  const _SheetContent({
    super.key,
    required this.post,
    required this.selectedTags,
    required this.onTagPressed,
  });

  final Post post;
  final Set<String> selectedTags;
  final void Function(String) onTagPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final rating = post.rating.describe(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rating.isNotEmpty)
            _InfoTile(title: context.t.rating.title, content: Text(rating)),
          _InfoTile(
            title: context.t.score,
            content: Text(post.score.toString()),
          ),
          if (post.postUrl.contains(post.id.toString()))
            _InfoTile(
              title: context.t.location,
              content: _LinkText(post.postUrl),
              trailing: _CopyButton(post.postUrl),
            ),
          if (post.source.isNotEmpty)
            _InfoTile(
              title: context.t.source,
              content: _LinkText(post.source),
              trailing: _CopyButton(post.source),
            ),
          if (post.sampleFile.isNotEmpty)
            _InfoTile(
              title: context.t.fileSample,
              content: FutureBuilder<PixelSize>(
                future:
                    (post.content.isPhoto || post.content.isGif) &&
                        !post.sampleSize.hasPixels
                    ? CachedNetworkImageProvider(
                        post.sampleFile,
                        headers: headers,
                      ).resolvePixelSize()
                    : Future.value(post.sampleSize),
                builder: (context, snapshot) {
                  final size = snapshot.data ?? post.sampleSize;
                  return _LinkText(
                    post.sampleFile,
                    label: '$size, ${post.sampleFile.fileExt}',
                  );
                },
              ),
              trailing: _CopyButton(post.sampleFile),
            ),
          _InfoTile(
            title: context.t.fileOg,
            content: _LinkText(
              post.originalFile,
              label:
                  '${post.originalSize.toString()}, ${post.originalFile.fileExt}',
            ),
            trailing: _CopyButton(post.originalFile),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(context.t.tags, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: DesignTokens.spacingSm),
          if (!post.hasCategorizedTags)
            _TagsWrap(
              tags: post.tags,
              selectedTags: selectedTags,
              onTagPressed: onTagPressed,
            )
          else ...[
            if (post.tagsMeta.isNotEmpty)
              _TagsSection(
                label: context.t.meta,
                tags: post.tagsMeta,
                selectedTags: selectedTags,
                onTagPressed: onTagPressed,
              ),
            if (post.tagsArtist.isNotEmpty)
              _TagsSection(
                label: context.t.artist,
                tags: post.tagsArtist,
                selectedTags: selectedTags,
                onTagPressed: onTagPressed,
              ),
            if (post.tagsCharacter.isNotEmpty)
              _TagsSection(
                label: context.t.character,
                tags: post.tagsCharacter,
                selectedTags: selectedTags,
                onTagPressed: onTagPressed,
              ),
            if (post.tagsCopyright.isNotEmpty)
              _TagsSection(
                label: context.t.copyright,
                tags: post.tagsCopyright,
                selectedTags: selectedTags,
                onTagPressed: onTagPressed,
              ),
            if (post.tagsGeneral.isNotEmpty)
              _TagsSection(
                label: context.t.general,
                tags: post.tagsGeneral,
                selectedTags: selectedTags,
                onTagPressed: onTagPressed,
              ),
          ],
          const SizedBox(height: DesignTokens.spacingXl * 3),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.content, this.trailing});

  final String title;
  final Widget content;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                content,
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText(this.url, {this.label});

  final String url;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrlString(url, mode: LaunchMode.externalApplication),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Text(label!, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            url,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 18,
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t.copySuccess),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      icon: const Icon(Icons.copy),
    );
  }
}

class _TagsSection extends StatelessWidget {
  const _TagsSection({
    required this.label,
    required this.tags,
    required this.selectedTags,
    required this.onTagPressed,
  });

  final String label;
  final List<String> tags;
  final Set<String> selectedTags;
  final void Function(String) onTagPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _TagsWrap(
          tags: tags,
          selectedTags: selectedTags,
          onTagPressed: onTagPressed,
        ),
      ],
    );
  }
}

class _TagsWrap extends StatelessWidget {
  const _TagsWrap({
    required this.tags,
    required this.selectedTags,
    required this.onTagPressed,
  });

  final List<String> tags;
  final Set<String> selectedTags;
  final void Function(String) onTagPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags.map((tag) {
        final isSelected = selectedTags.contains(tag);
        return FilterChip(
          label: Text(tag),
          labelPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          selected: isSelected,
          showCheckmark: false,
          onSelected: (_) => onTagPressed(tag),
        );
      }).toList(),
    );
  }
}
