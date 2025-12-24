import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
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
    this.onSheetChanged,
  });

  final Post post;
  final DraggableScrollableController sheetController;
  final ValueChanged<double>? onSheetChanged;

  @override
  State<PostDetailsSheet> createState() => _PostDetailsSheetState();
}

class _PostDetailsSheetState extends State<PostDetailsSheet> {
  final _contentScrollController = ScrollController();
  bool _isAtTop = true;

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
      _isAtTop = atTop;
    }
  }

  void _closeSheet() {
    // First scroll content to top if not already there
    if (_contentScrollController.hasClients &&
        _contentScrollController.offset > 0) {
      _contentScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // Then close the sheet
    widget.sheetController.animateTo(
      _kMinSheetSize,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is OverscrollNotification) {
          // Only close sheet on overscroll at top when content is at top
          if (notification.overscroll < -6 &&
              notification.depth == 0 &&
              _isAtTop) {
            _closeSheet();
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
                // Content
                Expanded(
                  child: _SheetContent(
                    post: widget.post,
                    contentScrollController: _contentScrollController,
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

class _SheetContent extends ConsumerWidget {
  const _SheetContent({
    required this.post,
    required this.contentScrollController,
  });

  final Post post;
  final ScrollController contentScrollController;

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
          _TagsWrap(tags: post.tags, ref: ref)
        else ...[
          if (post.tagsMeta.isNotEmpty)
            _TagsSection(label: context.t.meta, tags: post.tagsMeta, ref: ref),
          if (post.tagsArtist.isNotEmpty)
            _TagsSection(
                label: context.t.artist, tags: post.tagsArtist, ref: ref),
          if (post.tagsCharacter.isNotEmpty)
            _TagsSection(
                label: context.t.character, tags: post.tagsCharacter, ref: ref),
          if (post.tagsCopyright.isNotEmpty)
            _TagsSection(
                label: context.t.copyright, tags: post.tagsCopyright, ref: ref),
          if (post.tagsGeneral.isNotEmpty)
            _TagsSection(
                label: context.t.general, tags: post.tagsGeneral, ref: ref),
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
    required this.ref,
  });

  final String label;
  final List<String> tags;
  final WidgetRef ref;

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
        _TagsWrap(tags: tags, ref: ref),
      ],
    );
  }
}

class _TagsWrap extends StatelessWidget {
  const _TagsWrap({required this.tags, required this.ref});

  final List<String> tags;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags.map((tag) {
        return ActionChip(
          label: Text(tag),
          labelPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: () {
            // Copy tag to clipboard
            Clipboard.setData(ClipboardData(text: tag));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied: $tag'),
                duration: const Duration(seconds: 1),
                action: SnackBarAction(
                  label: context.t.actionTag.block,
                  onPressed: () {
                    ref
                        .read(tagsBlockerStateProvider.notifier)
                        .pushAll(tags: [tag]);
                  },
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }
}
