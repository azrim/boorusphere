import 'dart:async';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/booru_rating.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomeSearchBar extends HookConsumerWidget {
  const HomeSearchBar({super.key});

  /// Rendered height of the bar, bottom safe-area inset included. Chrome that
  /// floats above it (the pagination pill, back to top, the long-press hint,
  /// the grid's bottom padding) reads this instead of assuming a fixed
  /// height, so all of it follows font scaling.
  static final ValueNotifier<double> height = ValueNotifier(
    kBottomNavigationBarHeight + DesignTokens.spacingMd,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final searchBar = ref.watch(searchBarControllerProvider(session));
    final rating = ref.watch(
      serverSettingStateProvider.select((it) => it.searchRating),
    );

    return RepaintBoundary(
      child: _MeasureSize(
        onChange: (size) => height.value = size.height,
        child: Container(
          decoration: BoxDecoration(
            color: context.theme.scaffoldBackgroundColor,
            border: Border(
              top: BorderSide(color: context.colorScheme.outlineVariant),
            ),
          ),
          // No maintained bottom padding: when the IME is up the bar should
          // sit on the keyboard instead of keeping the nav-bar gap above it.
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (searchBar.isOpen) const _OptionBar(),
                Container(
                  decoration: BoxDecoration(
                    color: context.colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(DesignTokens.radiusLg),
                    ),
                  ),
                  margin: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd - DesignTokens.spacingXs,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd - DesignTokens.spacingXs,
                  ),
                  child: Row(
                    children: [
                      const _LeadingButton(),
                      const Expanded(child: _SearchField()),
                      // An active non-default rating is a state, so it gets a
                      // chip here instead of a 9 sp corner badge.
                      if (!searchBar.isOpen && rating != BooruRating.all)
                        const _CollapsedRatingChip(),
                      if (!searchBar.isOpen) const _TrailingButton(),
                      if (searchBar.isOpen &&
                          searchBar.value != searchBar.initial)
                        _Button(
                          onTap: searchBar.reset,
                          tooltip: context.t.resetQuery,
                          child: const Icon(Icons.rotate_left),
                        ),
                      if (searchBar.isOpen)
                        _Button(
                          onTap: searchBar.clear,
                          tooltip: context.t.clearQuery,
                          child: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends HookConsumerWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imeIncognito = ref.watch(
      uiSettingStateProvider.select((it) => it.imeIncognito),
    );
    final session = ref.watch(searchSessionProvider);
    final searchBar = ref.watch(searchBarControllerProvider(session));
    final server = ref.watch(serverStateProvider).getById(session.serverId);

    final hint = context.t.searchHint(serverName: server.name);
    final field = TextField(
      autofocus: searchBar.isOpen,
      canRequestFocus: searchBar.isOpen,
      enableIMEPersonalizedLearning: !imeIncognito,
      controller: searchBar.textEditingController,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: hint,
        isDense: true,
      ),
      textAlign: searchBar.isOpen ? TextAlign.start : TextAlign.center,
      readOnly: !searchBar.isOpen,
      onSubmitted: (str) {
        searchBar.submit(context, str);
      },
      onTap: searchBar.isOpen ? null : searchBar.open,
      style: DefaultTextStyle.of(context).style,
      // Optimize text input performance
      maxLines: 1,
      textInputAction: TextInputAction.search,
    );

    return RepaintBoundary(
      // Closed, the field is a button that opens search. Announcing it as a
      // read-only text field made the hint and the label repeat, and hid the
      // fact that it does something.
      child: searchBar.isOpen
          ? field
          : Semantics(
              button: true,
              label: hint,
              onTap: searchBar.open,
              child: ExcludeSemantics(child: field),
            ),
    );
  }
}

class _OptionBar extends StatelessWidget {
  const _OptionBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
        DesignTokens.spacingMd,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [_RatingButton()],
      ),
    );
  }
}

class _RatingButton extends ConsumerWidget {
  const _RatingButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref.watch(
      serverSettingStateProvider.select((it) => it.searchRating),
    );

    return ActionChip(
      avatar: const Icon(Icons.star_outline, size: DesignTokens.iconInline),
      label: Text(_ratingLabel(context, rating)),
      onPressed: () async {
        final selected = await _pickRating(context, rating);
        if (selected != null) {
          await ref
              .read(serverSettingStateProvider.notifier)
              .setRating(selected);
        }
      },
    );
  }
}

/// Rating name, with the unrated value spelled out.
String _ratingLabel(BuildContext context, BooruRating rating) {
  final desc = rating.describe(context);
  return desc.isEmpty ? context.t.rating.all : desc;
}

/// Rating picker shared by the option bar and the collapsed bar chip.
Future<BooruRating?> _pickRating(BuildContext context, BooruRating current) {
  return showDialog<BooruRating>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(context.t.rating.title),
        icon: const Icon(Icons.star),
        contentPadding: const EdgeInsets.only(top: 16, bottom: 16),
        content: RadioGroup<BooruRating>(
          groupValue: current,
          onChanged: (x) {
            context.navigator.pop(x);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: BooruRating.values
                .map(
                  (e) => ListTile(
                    leading: Radio<BooruRating>(value: e),
                    title: Text(_ratingLabel(context, e)),
                    onTap: () {
                      context.navigator.pop(e);
                    },
                  ),
                )
                .toList(),
          ),
        ),
      );
    },
  );
}

class _Button extends StatelessWidget {
  const _Button({required this.onTap, this.child, this.tooltip});

  final void Function() onTap;
  final Widget? child;

  /// Doubles as the accessible name, so every icon button in the bar needs one.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: DesignTokens.controlHeightMin,
        minHeight: DesignTokens.controlHeightMin,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Center(child: child),
      ),
    );

    final tooltip = this.tooltip;
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }
}

class _LeadingButton extends ConsumerWidget {
  const _LeadingButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final server = ref.watch(serverStateProvider).getById(session.serverId);
    final searchBar = ref.watch(searchBarControllerProvider(session));

    return _Button(
      tooltip: searchBar.isOpen
          ? context.t.cancel
          : context.t.sidebar.openNavigation,
      onTap: () {
        if (searchBar.isOpen) {
          searchBar.close();
        } else {
          Scaffold.of(context).openDrawer();
        }
      },
      child: searchBar.isOpen
          ? const Icon(Icons.arrow_back_rounded)
          : Favicon(
              key: ValueKey(server.homepage),
              url: server.homepage,
              iconSize: DesignTokens.iconInline,
            ),
    );
  }
}

/// Active non-default rating, shown in the collapsed bar. A filtered feed is
/// a state the user has to be able to see, not a badge to decode.
class _CollapsedRatingChip extends ConsumerWidget {
  const _CollapsedRatingChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref.watch(
      serverSettingStateProvider.select((it) => it.searchRating),
    );
    final badge = ratingBadgeOf(rating, context.colorScheme);
    if (badge == null) return const SizedBox.shrink();

    final label = '${context.t.rating.title}: ${_ratingLabel(context, rating)}';

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: DesignTokens.controlHeightMin,
            minHeight: DesignTokens.controlHeightMin,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            onTap: () async {
              final selected = await _pickRating(context, rating);
              if (selected != null) {
                await ref
                    .read(serverSettingStateProvider.notifier)
                    .setRating(selected);
              }
            },
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: DesignTokens.iconInline,
                    color: badge.color,
                  ),
                  const SizedBox(width: DesignTokens.spacingXs),
                  Text(
                    badge.label,
                    style: context.theme.textTheme.labelMedium?.copyWith(
                      color: badge.color,
                      fontWeight: FontWeight.w700,
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
}

/// Grid density. One slot, one job: the back-to-top control lives over the
/// grid, so this button never changes meaning mid-scroll.
class _TrailingButton extends ConsumerWidget {
  const _TrailingButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = ref.watch(uiSettingStateProvider.select((ui) => ui.grid));

    return _Button(
      tooltip: context.t.changeGrid,
      onTap: ref.read(uiSettingStateProvider.notifier).cycleGrid,
      child: Icon(key: ValueKey(grid), Icons.grid_view, size: 20),
    );
  }
}

/// Reports its child's laid-out size once per change.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size) return;
    _reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(size));
  }
}
