import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/utils/entity/pixel_size.dart';
import 'package:boorusphere/presentation/utils/extensions/images.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

const _kMinSheetSize = 0.0;
const _kSnapSheetSize = 0.5;
const _kMaxSheetSize = 0.9;

class PostDetailsSheet extends StatefulWidget {
  const PostDetailsSheet({
    super.key,
    required this.post,
    required this.sheetController,
    required this.session,
    this.onSheetChanged,
  });

  final Post post;
  final DraggableScrollableController sheetController;
  final SearchSession session;
  final ValueChanged<double>? onSheetChanged;

  @override
  State<PostDetailsSheet> createState() => _PostDetailsSheetState();
}

class _PostDetailsSheetState extends State<PostDetailsSheet> {
  final _contentScrollController = ScrollController();
  bool _isAtTop = true;
  bool _isScrollingToTop = false;
  final Set<String> _selectedTags = {};

  @override
  void initState() {
    super.initState();
    _contentScrollController.addListener(_onContentScroll);
  }

  @override
  void dispose() {
    _contentScrollController.removeListener(_onContentScroll);
    _contentScrollController.dispose();
    super.dispose();
  }

  void _onContentScroll() {
    final atTop = _contentScrollController.offset <= 0;
    if (atTop != _isAtTop) {
      setState(() {
        _isAtTop = atTop;
      });
    }
  }

  void _scrollToTopFirst() {
    if (_isScrollingToTop) return;

    _isScrollingToTop = true;
    _contentScrollController
        .animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        )
        .then(_onScrollToTopComplete);
  }

  void _onScrollToTopComplete(_) {
    _isScrollingToTop = false;
  }

  void _closeSheet() {
    widget.sheetController.animateTo(
      _kMinSheetSize,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
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
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Handle overscroll on the content ListView
        if (notification is OverscrollNotification &&
            notification.depth == 1 &&
            notification.overscroll < 0) {
          // User is trying to scroll up past the top of content
          if (_isAtTop) {
            _closeSheet();
          }
          return true;
        }

        // Handle scroll updates on the DraggableScrollableSheet
        if (notification is ScrollUpdateNotification &&
            notification.depth == 0) {
          // If user is dragging the sheet down but content is not at top
          if (notification.scrollDelta != null &&
              notification.scrollDelta! < 0 &&
              !_isAtTop) {
            // Scroll content to top first
            _scrollToTopFirst();
            return true; // Consume the notification
          }
        }

        return false;
      },
      child: DraggableScrollableSheet(
        controller: widget.sheetController,
        initialChildSize: _kMinSheetSize,
        minChildSize: _kMinSheetSize,
        maxChildSize: _kMaxSheetSize,
        snapSizes: const [_kMinSheetSize, _kSnapSheetSize, _kMaxSheetSize],
        snap: true,
        snapAnimationDuration: const Duration(milliseconds: 200),
        builder: (context, scrollController) {
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Drag handle
                _DragHandle(scrollController: scrollController),
                // Tag action bar when tags are selected
                if (_selectedTags.isNotEmpty)
                  _TagActionBar(
                    selectedTags: _selectedTags,
                    session: widget.session,
                    onClearSelection: _clearSelection,
                  ),
                // Content
                Expanded(
                  child: _SheetContent(
                    post: widget.post,
                    contentScrollController: _contentScrollController,
                    selectedTags: _selectedTags,
                    onTagPressed: _onTagPressed,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true, // Prevent bubbling
      child: SingleChildScrollView(
        controller: scrollController,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
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
    );
  }
}

class _SheetContent extends ConsumerWidget {
  const _SheetContent({
    required this.post,
    required this.contentScrollController,
    required this.selectedTags,
    required this.onTagPressed,
  });

  final Post post;
  final ScrollController contentScrollController;
  final Set<String> selectedTags;
  final void Function(String) onTagPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final rating = post.rating.describe(context);

    return ListView(
      controller: contentScrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (rating.isNotEmpty)
          _InfoTile(
            title: context.t.rating.title,
            content: Text(rating),
          ),
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
              future: (post.content.isPhoto || post.content.isGif) &&
                      !post.sampleSize.hasPixels
                  ? ExtendedNetworkImageProvider(
                      post.sampleFile,
                      cache: true,
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
        const SizedBox(height: 8),
        Text(
          context.t.tags,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 100),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.title,
    required this.content,
    this.trailing,
  });

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
            Text(
              label!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
