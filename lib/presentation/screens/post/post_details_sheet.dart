import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/entity/pixel_size.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/images.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:boorusphere/presentation/widgets/drag_handle.dart';
import 'package:boorusphere/presentation/widgets/sheet_row.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/url_validator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

const _kMinSheetSize = 0.0;

/// Index of the panel the sheet is showing.
enum _Panel { details, tags, links }

class PostDetailsSheet extends ConsumerStatefulWidget {
  const PostDetailsSheet({
    super.key,
    required this.postNotifier,
    required this.sheetController,
    required this.session,
  });

  /// How much of the viewer the sheet covers when it opens. It is also the
  /// tallest the sheet gets, so one downward drag dismisses it instead of
  /// walking through intermediate stops.
  static const double openSize = 0.75;

  final ValueNotifier<Post> postNotifier;
  final DraggableScrollableController sheetController;
  final SearchSession session;

  @override
  ConsumerState<PostDetailsSheet> createState() => _PostDetailsSheetState();
}

class _PostDetailsSheetState extends ConsumerState<PostDetailsSheet>
    with SingleTickerProviderStateMixin {
  /// Share of the sheet's width a drag covers before it commits — the same
  /// half-page rule the platform pagers use.
  static const double _commitFraction = 0.5;

  /// A flick this fast commits without waiting for the half-way mark.
  static const double _flingVelocity = 250;

  final Set<String> _selectedTags = {};
  int? _lastPostId;
  _Panel _panel = _Panel.details;

  /// How far the panels have travelled, in pages: -1 means the next panel has
  /// arrived, 1 the previous one, and 0 is settled.
  double _fraction = 0;

  /// The neighbouring panel travelling alongside, while a drag or a tab switch
  /// is in flight.
  _Panel? _incomingPanel;

  bool _dragging = false;

  /// Start and end of the settle animation, in pages.
  double _from = 0;
  double _to = 0;

  /// The widget built for [_incomingPanel], reused across the frames of one
  /// gesture so a long tag list is not laid out again on every tick.
  Widget? _incomingWidget;
  _Panel? _builtPanel;
  int? _builtPostId;

  late final AnimationController _panelAnimation = AnimationController(
    vsync: this,
    duration: DesignTokens.durationNormal,
  )..addStatusListener(_onPanelAnimationStatus);

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
    _panelAnimation.dispose();
    widget.postNotifier.removeListener(_onPostChanged);
    super.dispose();
  }

  /// Where the panels sit right now, in pages: the finger while it is down,
  /// the settle animation after it lifts.
  double get _travelled => _dragging
      ? _fraction
      : _from +
            (_to - _from) *
                DesignTokens.curveStandard.transform(_panelAnimation.value);

  /// The panel [offset] pages away, or null at either end of the strip.
  _Panel? _panelAt(int offset) {
    final index = _panel.index - offset;
    if (index < 0 || index >= _Panel.values.length) return null;
    return _Panel.values[index];
  }

  void _onPanelAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;

    final offset = _to == 0 ? 0 : (_to < 0 ? -1 : 1);
    setState(() {
      if (offset != 0) _panel = _panelAt(offset)!;
      _fraction = 0;
      _from = 0;
      _to = 0;
      _incomingPanel = null;
      _incomingWidget = null;
    });
  }

  /// Runs the panels to [to] pages and hands over when they land.
  void _settle(double to) {
    final from = _travelled;
    setState(() {
      _dragging = false;
      _from = from;
      _to = to;
    });
    _panelAnimation
      ..duration = context.motionDuration(DesignTokens.durationNormal)
      ..forward(from: 0);
  }

  void _goToPanel(int index) {
    if (index < 0 || index >= _Panel.values.length) return;
    if (index == _panel.index) return;

    final offset = index > _panel.index ? -1 : 1;
    setState(() {
      _dragging = false;
      _from = 0;
      _to = offset.toDouble();
      _incomingPanel = _panelAt(offset);
      _incomingWidget = null;
    });
    _panelAnimation
      ..duration = context.motionDuration(DesignTokens.durationNormal)
      ..forward(from: 0);
  }

  void _onDragStart(DragStartDetails details) {
    _panelAnimation.stop();
    setState(() {
      _dragging = true;
      _fraction = 0;
      _from = 0;
      _to = 0;
      _incomingPanel = null;
      _incomingWidget = null;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final width = context.size?.width ?? 0;
    if (width == 0) return;

    var next = _fraction + details.delta.dx / width;
    final neighbour = _panelAt(next < 0 ? -1 : 1);

    // At either end the panel only leans, so the edge is felt instead of the
    // gesture silently doing nothing.
    if (neighbour == null) {
      next = _fraction + details.delta.dx / width * 0.25;
    }

    setState(() {
      _fraction = next.clamp(-1.0, 1.0);
      if (_incomingPanel != neighbour) {
        _incomingPanel = neighbour;
        _incomingWidget = null;
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final direction = _fraction < 0 ? -1 : 1;
    final fling =
        velocity.abs() >= _flingVelocity &&
        velocity.isNegative == (direction < 0);
    final commit =
        _panelAt(direction) != null &&
        (_fraction.abs() >= _commitFraction || fling);

    _settle(commit ? direction.toDouble() : 0);
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

  Widget _panelBody(Post post, Map<String, String> headers) {
    final current = _panelOf(_panel, post, headers);
    final incomingPanel = _incomingPanel;
    if (incomingPanel == null || _travelled == 0) return current;

    final incoming = _incomingWidgetFor(incomingPanel, post, headers);

    return AnimatedBuilder(
      animation: _panelAnimation,
      builder: (context, _) {
        final travelled = _travelled;

        return ClipRect(
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              FractionalTranslation(
                translation: Offset(travelled, 0),
                child: current,
              ),
              FractionalTranslation(
                // The neighbour waits one page away on the side the strip is
                // travelling from.
                translation: Offset(travelled + (travelled < 0 ? 1 : -1), 0),
                child: incoming,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the neighbouring panel once per gesture, so dragging across a long
  /// tag list does not lay it out again on every frame.
  Widget _incomingWidgetFor(
    _Panel panel,
    Post post,
    Map<String, String> headers,
  ) {
    if (_incomingWidget == null ||
        _builtPanel != panel ||
        _builtPostId != post.id) {
      _incomingWidget = _panelOf(panel, post, headers);
      _builtPanel = panel;
      _builtPostId = post.id;
    }

    return _incomingWidget!;
  }

  Widget _panelOf(_Panel panel, Post post, Map<String, String> headers) {
    return switch (panel) {
      _Panel.details => _DetailsPanel(post: post),
      _Panel.tags => _TagsPanel(
        post: post,
        selectedTags: _selectedTags,
        onTagPressed: _onTagPressed,
      ),
      _Panel.links => _LinksPanel(post: post, headers: headers),
    };
  }

  @override
  Widget build(BuildContext context) {
    final enableBlur = ref.watch(uiSettingStateProvider.select((s) => s.blur));
    // The sheet is an overlay, so it takes the container tone the sheet theme
    // gives every other sheet instead of the page tone behind the artwork.
    // Midnight keeps its black sheet: that theme has no tone to step to.
    final backgroundColor = AppSurfacePolicy.of(context).flat
        ? context.colorScheme.surface
        : context.colorScheme.surfaceContainer;

    return DraggableScrollableSheet(
      controller: widget.sheetController,
      initialChildSize: _kMinSheetSize,
      minChildSize: _kMinSheetSize,
      maxChildSize: PostDetailsSheet.openSize,
      snapSizes: const [_kMinSheetSize, PostDetailsSheet.openSize],
      snap: true,
      snapAnimationDuration: context.motionDuration(
        DesignTokens.durationNormal,
      ),
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
              final headers = ref.watch(postHeadersFactoryProvider(post));
              final content = Container(
                decoration: BoxDecoration(
                  // With the blur on the sheet is glass over the artwork:
                  // enough of the image reads through to keep the context,
                  // while the surface still holds the text contrast.
                  color: enableBlur
                      ? backgroundColor.withValues(alpha: 0.72)
                      : backgroundColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(DesignTokens.radiusXl),
                  ),
                  // The same hairline every other sheet gets from the theme:
                  // over bright artwork the top edge would otherwise dissolve.
                  border: Border(
                    top: BorderSide(color: context.colorScheme.outlineVariant),
                  ),
                ),
                child: Stack(
                  // Expanded so the scroll view — and with it the swipe and the
                  // drag-to-dismiss — covers the sheet's full height instead of
                  // stopping where the rows end.
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      // The swipe belongs to the whole sheet, not to the panel
                      // box: with a short panel most of the sheet is empty
                      // space, and a gesture that only works on the rows is a
                      // gesture nobody finds. Opaque so blank space counts.
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: _onDragStart,
                      onHorizontalDragUpdate: _onDragUpdate,
                      onHorizontalDragEnd: _onDragEnd,
                      child: SingleChildScrollView(
                        controller: scrollController,
                        // A short panel leaves the sheet with nothing to
                        // scroll, and a scroll view that cannot scroll cannot
                        // be dragged either — which is how the sheet is
                        // dismissed.
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const DragHandle(
                              margin: EdgeInsets.only(
                                top: DesignTokens.spacingCardInset,
                                bottom: DesignTokens.spacingXs,
                              ),
                            ),
                            SheetTabs(
                              tabs: [
                                SheetTab(context.t.details),
                                SheetTab(
                                  context.t.tags,
                                  count: '${post.allTags.length}',
                                ),
                                SheetTab(
                                  context.t.links,
                                  count: '${_linkCount(post)}',
                                ),
                              ],
                              index: _panel.index,
                              onChanged: _goToPanel,
                            ),
                            AnimatedSize(
                              // Same duration as the panel sliding above it,
                              // so the sheet's edge and its content land
                              // together instead of the edge arriving early.
                              duration: context.motionDuration(
                                DesignTokens.durationNormal,
                              ),
                              curve: DesignTokens.curveStandard,
                              alignment: Alignment.topCenter,
                              child: _panelBody(post, headers),
                            ),
                            // The action bar floats over the panel, so the
                            // content only makes room for it while it is up.
                            SafeArea(
                              top: false,
                              child: SizedBox(
                                height: _selectedTags.isEmpty
                                    ? DesignTokens.spacingMd
                                    : DesignTokens.spacingXl * 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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

/// How many of the post's addresses the links panel will list.
int _linkCount(Post post) {
  var count = 0;
  if (post.postUrl.contains(post.id.toString())) count++;
  if (post.source.isNotEmpty) count++;
  if (post.sampleFile.isNotEmpty) count++;
  count++;
  return count;
}

void _copy(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.t.copySuccess),
      duration: const Duration(seconds: 1),
    ),
  );
}

void _open(String url) {
  if (isSafeUrl(url)) {
    launchUrlString(url, mode: LaunchMode.externalApplication);
  }
}

/// The numbers: what the post is and what it is made of.
class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final rating = post.rating.describe(context);
    final ext = post.originalFile.fileExt.toUpperCase();

    return SheetPanel(
      children: [
        if (rating.isNotEmpty)
          SheetFactRow(label: context.t.rating.title, value: rating),
        SheetFactRow(label: context.t.score, value: post.score.toString()),
        if (post.originalSize.hasPixels)
          SheetFactRow(
            label: context.t.dimensions,
            value: post.originalSize.toString(),
          ),
        if (ext.isNotEmpty) SheetFactRow(label: context.t.format, value: ext),
      ],
    );
  }
}

/// The addresses: where the post lives and where its files are.
class _LinksPanel extends StatelessWidget {
  const _LinksPanel({required this.post, required this.headers});

  final Post post;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final originalExt = post.originalFile.fileExt.toUpperCase();

    return SheetPanel(
      children: [
        if (post.postUrl.contains(post.id.toString()))
          SheetLinkRow(
            label: context.t.location,
            url: post.postUrl,
            onOpen: () => _open(post.postUrl),
            onCopy: () => _copy(context, post.postUrl),
          ),
        if (post.source.isNotEmpty)
          SheetLinkRow(
            label: context.t.source,
            url: post.source,
            onOpen: () => _open(post.source),
            onCopy: () => _copy(context, post.source),
          ),
        if (post.sampleFile.isNotEmpty)
          _SampleLinkRow(post: post, headers: headers),
        SheetLinkRow(
          label: context.t.fileOg,
          detail: '${post.originalSize}, $originalExt',
          url: post.originalFile,
          onOpen: () => _open(post.originalFile),
          onCopy: () => _copy(context, post.originalFile),
        ),
      ],
    );
  }
}

/// The sample row resolves the image's real pixel size once, so switching
/// panels does not re-request the header of an image that has not changed.
class _SampleLinkRow extends StatefulWidget {
  const _SampleLinkRow({required this.post, required this.headers});

  final Post post;
  final Map<String, String> headers;

  @override
  State<_SampleLinkRow> createState() => _SampleLinkRowState();
}

class _SampleLinkRowState extends State<_SampleLinkRow> {
  late Future<PixelSize> _size = _resolve();

  Future<PixelSize> _resolve() {
    final post = widget.post;
    if ((post.content.isPhoto || post.content.isGif) &&
        !post.sampleSize.hasPixels) {
      return CachedNetworkImageProvider(
        post.sampleFile,
        headers: widget.headers,
      ).resolvePixelSize();
    }

    return Future.value(post.sampleSize);
  }

  @override
  void didUpdateWidget(covariant _SampleLinkRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.sampleFile != widget.post.sampleFile) {
      _size = _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final ext = post.sampleFile.fileExt.toUpperCase();

    return FutureBuilder<PixelSize>(
      future: _size,
      builder: (context, snapshot) {
        // Until the size resolves the row says what it knows — the format —
        // instead of printing a placeholder where a measurement belongs.
        final size = snapshot.data ?? post.sampleSize;
        final detail = size.hasPixels ? '$size, $ext' : ext;

        return SheetLinkRow(
          label: context.t.fileSample,
          detail: detail,
          url: post.sampleFile,
          onOpen: () => _open(post.sampleFile),
          onCopy: () => _copy(context, post.sampleFile),
        );
      },
    );
  }
}

/// The tags, grouped by what they describe. A tap selects a tag; the action bar
/// at the bottom of the sheet then says what can be done with the selection.
class _TagsPanel extends StatelessWidget {
  const _TagsPanel({
    required this.post,
    required this.selectedTags,
    required this.onTagPressed,
  });

  final Post post;
  final Set<String> selectedTags;
  final void Function(String) onTagPressed;

  @override
  Widget build(BuildContext context) {
    if (!post.hasCategorizedTags) {
      return _Group(
        tags: post.tags,
        selectedTags: selectedTags,
        onTagPressed: onTagPressed,
      );
    }

    final groups = <(String, List<String>)>[
      (context.t.meta, post.tagsMeta),
      (context.t.artist, post.tagsArtist),
      (context.t.character, post.tagsCharacter),
      (context.t.copyright, post.tagsCopyright),
      (context.t.general, post.tagsGeneral),
    ].where((group) => group.$2.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, tags) in groups)
          _Group(
            label: label,
            tags: tags,
            selectedTags: selectedTags,
            onTagPressed: onTagPressed,
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.tags,
    required this.selectedTags,
    required this.onTagPressed,
    this.label,
  });

  final List<String> tags;
  final Set<String> selectedTags;
  final void Function(String) onTagPressed;

  /// The category this group describes; the uncategorised cloud has none.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label case final label?)
            Padding(
              padding: const EdgeInsets.only(
                bottom: DesignTokens.spacingSm + 2,
              ),
              child: Row(
                children: [
                  Text(
                    label.toUpperLocale(context),
                    style: sheetLabelStyle(context),
                  ),
                  const SizedBox(width: DesignTokens.spacingSm),
                  Text('${tags.length}', style: sheetLabelStyle(context)),
                ],
              ),
            ),
          Wrap(
            spacing: DesignTokens.spacingSm,
            runSpacing: DesignTokens.spacingSm,
            children: [
              for (final tag in tags)
                _TagChip(
                  tag: tag,
                  selected: selectedTags.contains(tag),
                  onTap: () => onTagPressed(tag),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  final String tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return FilterChip(
      label: Text(tag),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primaryContainer,
      labelStyle: context.theme.textTheme.bodySmall?.copyWith(
        color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
      ),
      shape: const StadiumBorder(),
      side: selected
          ? BorderSide.none
          : BorderSide(color: scheme.outlineVariant),
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
    final scheme = context.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingSm,
            vertical: DesignTokens.spacingXs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: DesignTokens.spacingSm),
                  child: Text(
                    context.t.batch.selected(n: selectedTags.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20),
                tooltip: context.t.actionTag.copy,
                onPressed: () {
                  _copy(context, selectedTags.join(' '));
                  onClearSelection();
                },
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
