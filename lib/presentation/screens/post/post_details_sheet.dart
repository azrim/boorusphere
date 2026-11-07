import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/screens/post/tag_info_sheet.dart';
import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/entity/pixel_size.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/images.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
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

/// The tallest the sheet gets, whatever the panel asks for. The tags panel
/// uses it; the shorter panels open below it.
const _kMaxSheetSize = 0.75;

/// How many chips a tag group lays out before it offers the rest. A general
/// tag cloud can run into the hundreds; laying all of it out to show twenty
/// on screen costs the sheet a frame every time a tag is toggled.
const _kGroupSoftLimit = 40;

/// Index of the panel the sheet is showing.
enum _Panel { details, tags, links }

class PostDetailsSheet extends ConsumerStatefulWidget {
  const PostDetailsSheet({
    super.key,
    required this.postNotifier,
    required this.sheetController,
    required this.openSize,
    required this.session,
  });

  /// The share used until the sheet has measured the current panel. The sheet
  /// publishes the measured value through [openSize].
  static const double initialOpenSize = 0.5;

  final ValueNotifier<Post> postNotifier;
  final DraggableScrollableController sheetController;

  /// How much of the viewer the current panel opens at. The viewer reads this
  /// when it is asked to open the sheet, so the sheet grows to the panel it is
  /// showing instead of always taking three quarters of the screen.
  final ValueNotifier<double> openSize;

  final SearchSession session;

  @override
  ConsumerState<PostDetailsSheet> createState() => _PostDetailsSheetState();
}

class _PostDetailsSheetState extends ConsumerState<PostDetailsSheet>
    with SingleTickerProviderStateMixin {
  /// Share of the sheet's width a drag covers before it commits; the same
  /// half-page rule the platform pagers use.
  static const double _commitFraction = 0.5;

  /// A flick this fast commits without waiting for the half-way mark.
  static const double _flingVelocity = 250;

  final Set<String> _selectedTags = {};
  int? _lastPostId;

  /// The panel the strip is settled on, and the one it is travelling to while
  /// a tab switch or a settle is in flight.
  _Panel _panel = _Panel.details;
  _Panel? _pending;
  int _displayIndex = 0;

  /// The adjacent panel the finger is currently pulling in, if any.
  _Panel? _dragTarget;

  bool _dragging = false;

  /// Where the strip sits, in pages: negative travels toward a later panel.
  /// It drives the translations directly, so a drag does not rebuild the sheet
  /// on every horizontal delta.
  final ValueNotifier<double> _travel = ValueNotifier(0);

  /// Start and end of the settle animation, in pages.
  double _from = 0;
  double _to = 0;

  late final AnimationController _panelAnimation = AnimationController(
    vsync: this,
    duration: DesignTokens.durationNormal,
  )..addStatusListener(_onPanelAnimationStatus);

  /// Everything the panel strip has to follow: the settle animation and, while
  /// the finger is down, the raw drag.
  late final Listenable _strip = Listenable.merge([_panelAnimation, _travel]);

  /// Whether the sheet has any height. The closed sheet keeps its scroll view
  /// (the draggable controller attaches through it) but not its content.
  bool _open = false;

  ScrollController? _scroll;

  /// The snap sizes handed to the sheet, cached so an unrelated rebuild does
  /// not look like a settings change and force a snap.
  List<double> _snapSizes = const [PostDetailsSheet.initialOpenSize];

  @override
  void initState() {
    super.initState();
    _lastPostId = widget.postNotifier.value.id;
    widget.postNotifier.addListener(_onPostChanged);
    widget.sheetController.addListener(_onSheetExtent);
    _panelAnimation.addListener(_syncDisplayIndex);
    _travel.addListener(_syncDisplayIndex);
  }

  @override
  void didUpdateWidget(covariant PostDetailsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.postNotifier, widget.postNotifier)) {
      oldWidget.postNotifier.removeListener(_onPostChanged);
      widget.postNotifier.addListener(_onPostChanged);
      _lastPostId = widget.postNotifier.value.id;
    }
    if (!identical(oldWidget.sheetController, widget.sheetController)) {
      oldWidget.sheetController.removeListener(_onSheetExtent);
      widget.sheetController.addListener(_onSheetExtent);
      _open = false;
    }
  }

  @override
  void dispose() {
    widget.postNotifier.removeListener(_onPostChanged);
    widget.sheetController.removeListener(_onSheetExtent);
    _panelAnimation.dispose();
    _travel.dispose();
    super.dispose();
  }

  /// Where the panels sit right now, in pages: the finger while it is down,
  /// the settle animation after it lifts.
  double get _travelled {
    if (_dragging) return _travel.value;
    if (_from == _to) return _to;

    return _from +
        (_to - _from) *
            DesignTokens.curveStandard.transform(_panelAnimation.value);
  }

  /// The panel [offset] pages away, or null at either end of the strip.
  /// Negative offsets travel toward later panels, positive toward earlier.
  _Panel? _panelAt(int offset) {
    final index = _panel.index - offset;
    if (index < 0 || index >= _Panel.values.length) return null;
    return _Panel.values[index];
  }

  void _onSheetExtent() {
    if (!mounted || !widget.sheetController.isAttached) return;

    final open = widget.sheetController.size > 0.001;
    if (open != _open) {
      setState(() => _open = open);
    }
  }

  void _onPanelAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;

    final destination = _to == 0 ? null : _pending;
    setState(() {
      if (destination != null) _panel = destination;
      _pending = null;
      _dragTarget = null;
      _dragging = false;
      _from = 0;
      _to = 0;
      _displayIndex = _panel.index;
    });
    _travel.value = 0;

    // The next panel starts at its own top; carrying the previous panel's
    // scroll offset would open a short panel half scrolled.
    if (destination != null) _resetScroll();
  }

  void _syncDisplayIndex() {
    if (!mounted) return;

    final target = _pending ?? _dragTarget;
    final index = target != null && _travelled.abs() >= _commitFraction
        ? target.index
        : _panel.index;
    if (index != _displayIndex) {
      setState(() => _displayIndex = index);
    }
  }

  void _resetScroll() {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients || scroll.offset == 0) return;
    scroll.jumpTo(0);
  }

  /// The slide's duration, shortened for short moves so a nudge back home is
  /// not answered with a full page's travel time.
  Duration _slideDuration(double pages) {
    final milliseconds =
        (DesignTokens.durationNormal.inMilliseconds *
                pages.abs().clamp(0.25, 1.0))
            .round()
            .clamp(
              DesignTokens.durationFast.inMilliseconds,
              DesignTokens.durationNormal.inMilliseconds,
            );

    return context.motionDuration(Duration(milliseconds: milliseconds));
  }

  double _targetFor(_Panel panel, double viewportHeight) {
    final height = viewportHeight <= 0 ? 800.0 : viewportHeight;
    final bottom = context.mqPadding.bottom;

    final (fraction, pixels) = switch (panel) {
      // Four fact rows: the sheet opens around them instead of borrowing the
      // tags panel's three quarters of the screen.
      _Panel.details => (0.5, _detailsPixels(bottom)),
      _Panel.links => (0.62, 520.0 + bottom),
      _Panel.tags => (_kMaxSheetSize, 820.0 + bottom),
    };

    return math.min(fraction, pixels / height).clamp(0.28, _kMaxSheetSize);
  }

  double _detailsPixels(double bottomInset) {
    final post = widget.postNotifier.value;
    final rows =
        (post.rating.describe(context).isEmpty ? 0 : 1) +
        1 + // score
        (post.originalSize.hasPixels ? 1 : 0) +
        (post.originalFile.fileExt.toUpperCase().isEmpty ? 0 : 1);

    // handle + tabs + ruled rows + the spacer under the panel
    return 16 + 48 + rows * 48.0 + (rows - 1) + 16 + bottomInset;
  }

  void _publishOpenSize(double target) {
    if (widget.openSize.value != target) {
      widget.openSize.value = target;
    }
  }

  void _syncSnapSizes(double target) {
    if (_snapSizes.length != 1 || _snapSizes.first != target) {
      _snapSizes = [target];
    }
  }

  /// Runs the strip to [to] pages. The sheet resizes with it when the strip
  /// lands on a new panel, so the edge and the content arrive together.
  void _animateStrip({required double to, required _Panel? destination}) {
    final from = _travelled;
    if (from == to && from == 0) {
      // Nothing left to travel. If a jump had just been asked for, its sheet
      // resize may already be running toward the panel this call cancels, so
      // the sheet is brought back with it instead of being left to grow for a
      // panel that is no longer coming.
      final wasJumping = _pending != null;
      setState(() {
        _dragging = false;
        _dragTarget = null;
        _pending = null;
      });
      if (wasJumping) {
        _animateSheetTo(
          _panel,
          context.motionDuration(DesignTokens.durationFast),
        );
      }
      return;
    }

    final duration = _slideDuration(to - from);
    setState(() {
      _dragging = false;
      _dragTarget = null;
      _pending = destination;
      _from = from;
      _to = to;
    });
    _panelAnimation
      ..stop()
      ..duration = duration
      ..forward(from: 0);

    // A home settle also returns the sheet to the current panel's size, which
    // undoes a resize that an interrupted tab switch had started.
    final sheetPanel = to != 0 && destination != null ? destination : _panel;
    _animateSheetTo(sheetPanel, duration);
    _syncDisplayIndex();
  }

  void _animateSheetTo(_Panel panel, Duration duration) {
    if (!widget.sheetController.isAttached) return;

    final target = _targetFor(panel, context.mqSize.height);
    // Reduced motion turns every duration into zero, which the controller
    // refuses; go straight to the height instead.
    if (duration == Duration.zero) {
      widget.sheetController.jumpTo(target);
      return;
    }

    widget.sheetController.animateTo(
      target,
      duration: duration,
      curve: DesignTokens.curveStandard,
    );
  }

  void _goToPanel(int index) {
    if (index < 0 || index >= _Panel.values.length) return;

    final target = _Panel.values[index];
    _panelAnimation.stop();

    if (target == _panel) {
      // Tapping the tab the sheet is already on brings a half-finished jump
      // home instead of starting a second one. The panel leaving the strip
      // stays built so it slides out rather than vanishing.
      _animateStrip(to: 0, destination: _pending);
      return;
    }

    final direction = target.index > _panel.index ? -1.0 : 1.0;
    _animateStrip(to: direction, destination: target);
  }

  void _onDragStart(DragStartDetails details) {
    _panelAnimation.stop();
    final from = _travelled;
    final direction = from < 0 ? -1 : (from > 0 ? 1 : 0);

    setState(() {
      _dragging = true;
      _pending = null;
      _dragTarget = direction == 0 ? null : _panelAt(direction);
      _from = 0;
      _to = 0;
    });
    _travel.value = from;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final width = context.size?.width ?? 0;
    if (width == 0) return;

    final delta = details.delta.dx / width;
    final next = (_travel.value + delta).clamp(-1.0, 1.0);
    final neighbour = _panelAt(next < 0 ? -1 : 1);

    // At either end the panel only leans, so the edge is felt instead of the
    // gesture silently doing nothing.
    _travel.value = neighbour == null
        ? (_travel.value + delta * 0.25).clamp(-1.0, 1.0)
        : next;

    if (_dragTarget != neighbour) {
      setState(() => _dragTarget = neighbour);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final travel = _travel.value;
    final direction = travel < 0 ? -1 : 1;
    final neighbour = _panelAt(direction);

    final bool commit;
    if (velocity.abs() >= _flingVelocity) {
      // A flick decides on its own, and a flick back home beats the distance
      // already dragged: the last gesture says what the reader wants.
      commit = neighbour != null && velocity.isNegative == (direction < 0);
    } else {
      commit = neighbour != null && travel.abs() >= _commitFraction;
    }

    final destination = travel == 0 && !commit ? null : neighbour;
    _animateStrip(
      to: commit ? direction.toDouble() : 0,
      destination: destination,
    );
  }

  void _onPostChanged() {
    if (!mounted) return;

    final newId = widget.postNotifier.value.id;
    final changed = _lastPostId != newId;
    _lastPostId = newId;

    // The panels follow the notifier on their own, but the height Details
    // publishes counts this post's rows, so the sheet has to rebuild to
    // republish it.
    setState(() {
      if (changed && _selectedTags.isNotEmpty) _selectedTags.clear();
    });
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

  /// Opens the tag's description from the server that owns this post.
  ///
  /// A post from an older library entry may predate [Post.serverId]; the
  /// session is the server the post is being viewed from, so it is the right
  /// fallback rather than the first server in the list.
  void _onTagLongPressed(String tag) {
    final post = widget.postNotifier.value;
    final serverId = post.serverId.isNotEmpty
        ? post.serverId
        : widget.session.serverId;
    final server = ref.read(serverStateProvider).getById(serverId);
    if (server == Server.empty) return;

    showTagInfoSheet(context, server: server, tag: tag);
  }

  void _clearSelection() {
    setState(_selectedTags.clear);
  }

  Widget _sheetBody(Post post) {
    final headers = ref.watch(postHeadersFactoryProvider(post));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DragHandle(),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.sheetContentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetTabs(
                  tabs: [
                    SheetTab(context.t.details),
                    SheetTab(context.t.tags, count: '${post.allTags.length}'),
                    SheetTab(context.t.links, count: '${_linkCount(post)}'),
                  ],
                  index: _displayIndex,
                  onChanged: _goToPanel,
                ),
                _panelBody(post, headers),
                // The action bar floats over the panel, so the content only
                // makes room for it while it is up.
                SafeArea(
                  top: false,
                  child: AnimatedContainer(
                    duration: context.motionDuration(DesignTokens.durationFast),
                    curve: DesignTokens.curveStandard,
                    height: _selectedTags.isEmpty
                        ? DesignTokens.spacingMd
                        : DesignTokens.spacingXl * 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _panelBody(Post post, Map<String, String> headers) {
    final target = _pending ?? _dragTarget;
    final current = _panelOf(_panel, post, headers, active: true);
    final incoming = target == null || target == _panel
        ? null
        : _panelOf(target, post, headers, active: false);

    return ClipRect(
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          _placed(current, 0),
          if (incoming != null)
            _placed(incoming, target!.index < _panel.index ? -1 : 1),
        ],
      ),
    );
  }

  /// Places one panel of the strip. Only the translation is rebuilt per tick;
  /// the panel itself is built once per composition, so a long tag list is not
  /// laid out again for every frame of a drag.
  Widget _placed(Widget child, int pageOffset) {
    return AnimatedBuilder(
      animation: _strip,
      child: child,
      builder: (context, child) => FractionalTranslation(
        translation: Offset(_travelled + pageOffset, 0),
        child: child,
      ),
    );
  }

  Widget _panelOf(
    _Panel panel,
    Post post,
    Map<String, String> headers, {
    required bool active,
  }) {
    return switch (panel) {
      _Panel.details => _DetailsPanel(post: post),
      _Panel.tags => _TagsPanel(
        post: post,
        selectedTags: _selectedTags,
        onTagPressed: _onTagPressed,
        onTagLongPressed: _onTagLongPressed,
      ),
      _Panel.links => _LinksPanel(
        post: post,
        headers: headers,
        resolveSample: active,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    // The sheet is an overlay, so it takes the container tone the sheet theme
    // gives every other sheet. Midnight keeps its black sheet: that theme has
    // no tone to step to.
    final backgroundColor = AppSurfacePolicy.of(context).flat
        ? scheme.surface
        : scheme.surfaceContainer;

    final viewport = context.mqSize.height;
    final target = _targetFor(_panel, viewport);
    _publishOpenSize(target);
    _syncSnapSizes(target);

    return DraggableScrollableSheet(
      controller: widget.sheetController,
      initialChildSize: _kMinSheetSize,
      minChildSize: _kMinSheetSize,
      maxChildSize: _kMaxSheetSize,
      snapSizes: _snapSizes,
      snap: true,
      snapAnimationDuration: context.motionDuration(
        DesignTokens.durationNormal,
      ),
      builder: (context, scrollController) {
        _scroll = scrollController;

        return RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              // Opaque on purpose: the rows are read against a surface known
              // from the first frame. Glass over artwork could not hold AA
              // contrast for the muted labels, and re-reading moving media
              // under a blur cost a frame every time the image changed.
              color: backgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DesignTokens.radiusXl),
              ),
              // The same hairline every other sheet gets from the theme: over
              // bright artwork the top edge would otherwise dissolve.
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DesignTokens.radiusXl),
              ),
              child: Stack(
                // Expanded so the scroll view (and with it the swipe and the
                // drag-to-dismiss) covers the sheet's full height instead of
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
                      // be dragged either, which is how the sheet is
                      // dismissed.
                      physics: const AlwaysScrollableScrollPhysics(),
                      // The scroll view stays mounted while the sheet is
                      // closed so the draggable controller can always attach;
                      // only the content it carries is dropped.
                      child: _open
                          ? ValueListenableBuilder<Post>(
                              valueListenable: widget.postNotifier,
                              builder: (context, post, child) =>
                                  _sheetBody(post),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  if (_open)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      // The bar rises with the selection and leaves the same
                      // way, so selecting a tag reads as one state change
                      // rather than a jump.
                      child: AnimatedSwitcher(
                        duration: context.motionDuration(
                          DesignTokens.durationFast,
                        ),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _selectedTags.isEmpty
                            ? const SizedBox.shrink()
                            : _TagActionBar(
                                key: const ValueKey('tag-action-bar'),
                                selectedTags: _selectedTags,
                                session: widget.session,
                                onClearSelection: _clearSelection,
                              ),
                      ),
                    ),
                ],
              ),
            ),
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
  // A post without an original file (an old library entry) has nothing to
  // open or copy, so the row and its count are not promised.
  if (post.originalFile.isNotEmpty) count++;
  return count;
}

void _copy(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  showToast(context, context.t.copySuccess);
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
  const _LinksPanel({
    required this.post,
    required this.headers,
    required this.resolveSample,
  });

  final Post post;
  final Map<String, String> headers;

  /// Whether this panel is the one on screen. The neighbour built for the
  /// drag only resolves the sample's size once it lands, so swiping past the
  /// links panel does not fetch a header it never showed.
  final bool resolveSample;

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
          _SampleLinkRow(post: post, headers: headers, resolve: resolveSample),
        if (post.originalFile.isNotEmpty)
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
  const _SampleLinkRow({
    required this.post,
    required this.headers,
    required this.resolve,
  });

  final Post post;
  final Map<String, String> headers;
  final bool resolve;

  @override
  State<_SampleLinkRow> createState() => _SampleLinkRowState();
}

class _SampleLinkRowState extends State<_SampleLinkRow> {
  late Future<PixelSize> _size = _resolve();

  Future<PixelSize> _resolve() {
    final post = widget.post;
    if (widget.resolve &&
        (post.content.isPhoto || post.content.isGif) &&
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
    if (oldWidget.post.sampleFile != widget.post.sampleFile ||
        (!oldWidget.resolve && widget.resolve)) {
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
        // Until the size resolves the row says what it knows: the format,
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

/// The tags, grouped by what they describe. A tap selects a tag; a long press
/// opens its description. The action bar at the bottom of the sheet then says
/// what can be done with the selection.
class _TagsPanel extends StatelessWidget {
  const _TagsPanel({
    required this.post,
    required this.selectedTags,
    required this.onTagPressed,
    required this.onTagLongPressed,
  });

  final Post post;
  final Set<String> selectedTags;
  final void Function(String) onTagPressed;
  final void Function(String) onTagLongPressed;

  @override
  Widget build(BuildContext context) {
    if (!post.hasCategorizedTags) {
      return _Group(
        tags: post.tags,
        selectedTags: selectedTags,
        onTagPressed: onTagPressed,
        onTagLongPressed: onTagLongPressed,
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
            onTagLongPressed: onTagLongPressed,
          ),
      ],
    );
  }
}

class _Group extends StatefulWidget {
  const _Group({
    required this.tags,
    required this.selectedTags,
    required this.onTagPressed,
    required this.onTagLongPressed,
    this.label,
  });

  final List<String> tags;
  final Set<String> selectedTags;
  final void Function(String) onTagPressed;
  final void Function(String) onTagLongPressed;

  /// The category this group describes; the uncategorised cloud has none.
  final String? label;

  @override
  State<_Group> createState() => _GroupState();
}

class _GroupState extends State<_Group> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tags = widget.tags;
    final collapsed = !_expanded && tags.length > _kGroupSoftLimit;
    final visible = collapsed ? tags.take(_kGroupSoftLimit) : tags;
    final hidden = collapsed ? tags.length - _kGroupSoftLimit : 0;
    // A tag the reader picked is never hidden behind the cap: a selection
    // that scrolls away is a selection they cannot see or undo.
    final pinned = collapsed
        ? tags.skip(_kGroupSoftLimit).where(widget.selectedTags.contains)
        : const <String>[];

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
          if (widget.label case final label?)
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
                  Text(
                    '${tags.length}',
                    style: sheetLabelStyle(context).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: DesignTokens.spacingSm,
            runSpacing: DesignTokens.spacingSm,
            children: [
              for (final tag in [...visible, ...pinned])
                _TagChip(
                  tag: tag,
                  selected: widget.selectedTags.contains(tag),
                  onTap: () => widget.onTagPressed(tag),
                  onLongPress: () => widget.onTagLongPressed(tag),
                ),
              if (hidden > 0)
                _ShowMoreChip(
                  count: hidden,
                  onPressed: () => setState(() => _expanded = true),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chip that opens the rest of a long group.
class _ShowMoreChip extends StatelessWidget {
  const _ShowMoreChip({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return Tooltip(
      message: context.t.actionTag.showMore(count: count),
      child: ActionChip(
        label: Text('+$count'),
        onPressed: onPressed,
        backgroundColor: scheme.surfaceContainerHighest,
        labelStyle: context.theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final String tag;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    // The chip handles the tap; the long press stays on the recogniser above
    // it, so selecting and describing a tag do not fight over the gesture.
    return GestureDetector(
      onLongPress: onLongPress,
      child: FilterChip(
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
      ),
    );
  }
}

class _TagActionBar extends ConsumerWidget {
  const _TagActionBar({
    super.key,
    required this.selectedTags,
    required this.session,
    required this.onClearSelection,
  });

  final Set<String> selectedTags;
  final SearchSession session;
  final VoidCallback onClearSelection;

  Future<void> _blockTags(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(tagsBlockerStateProvider.notifier);
    final tags = selectedTags.toList();
    // Only the tags this action adds may be undone by it; a tag that was
    // already blocked stays blocked.
    final alreadyBlocked = ref
        .read(tagsBlockerStateProvider)
        .values
        .where((tag) => tag.serverId.isEmpty)
        .map((tag) => tag.name)
        .toSet();

    await notifier.pushAll(tags: tags);
    if (!context.mounted) return;

    showToast(
      context,
      context.t.actionTag.blocked,
      actionLabel: context.t.undo,
      duration: DesignTokens.durationUndo,
      onAction: () {
        final added = tags
            .where((tag) => !alreadyBlocked.contains(tag.trim()))
            .toList();
        unawaited(notifier.removeAll(tags: added));
      },
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
    final flat = AppSurfacePolicy.of(context).flat;

    return Container(
      decoration: BoxDecoration(
        // The bar is chrome over the sheet: one tone above it, or the page
        // tone in Midnight where a step up would break the flat rule.
        color: flat ? scheme.surface : scheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.sheetContentMaxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingSm,
                vertical: DesignTokens.spacingXs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: DesignTokens.spacingSm,
                      ),
                      child: Text(
                        context.t.batch.selected(n: selectedTags.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextRoles.of(context).rowSupporting,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: DesignTokens.iconAction,
                    ),
                    tooltip: context.t.actionTag.copy,
                    onPressed: () {
                      _copy(context, selectedTags.join(' '));
                      onClearSelection();
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.block,
                      size: DesignTokens.iconAction,
                    ),
                    tooltip: context.t.actionTag.block,
                    onPressed: () {
                      unawaited(_blockTags(context, ref));
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                      size: DesignTokens.iconAction,
                    ),
                    tooltip: context.t.actionTag.append,
                    onPressed: () => _appendTags(context),
                  ),
                  // The one action the bar is asking for: a search built from
                  // the selection. It is the only filled control in the bar.
                  IconButton.filled(
                    icon: const Icon(
                      Icons.search,
                      size: DesignTokens.iconAction,
                    ),
                    tooltip: context.t.actionTag.search,
                    onPressed: () => _searchTags(context),
                  ),
                  IconButton(
                    // The X read as "close the sheet"; deselect says what
                    // the control actually does.
                    icon: const Icon(
                      Icons.deselect,
                      size: DesignTokens.iconAction,
                    ),
                    tooltip: context.t.clear,
                    onPressed: onClearSelection,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
