import 'dart:async';
import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomeSearchBar extends HookConsumerWidget {
  const HomeSearchBar({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final searchBar = ref.watch(searchBarControllerProvider(session));
    final delta = useState([0.0, 0.0]);
    final collapsed = !searchBar.isOpen && delta.value.first > 0;
    final isBlurAllowed = ref.watch(
      uiSettingStateProvider.select((ui) => ui.blur),
    );

    // Disable scroll listener when search is open for better performance
    final onScrolling = useCallback(() {
      if (searchBar.isOpen) return; // Skip when search is open

      final position = scrollController.position;
      final threshold = innerHeight;

      // Reset when scrolled to top
      if (position.pixels <= 0) {
        if (delta.value.first != 0 || delta.value.last != 0) {
          delta.value = [0, 0];
        }
        return;
      }

      if (delta.value.first > 0 &&
          position.viewportDimension > position.maxScrollExtent) {
        delta.value = [0, 0];
        return;
      }

      if (position.extentBefore < threshold ||
          position.extentAfter < threshold) {
        return;
      }

      final current = position.pixels;
      final offset = (delta.value.first + current - delta.value.last);
      final boundary = offset.clamp(-threshold, threshold);

      if ((boundary - delta.value.first).abs() > 10) {
        // Increased threshold
        delta.value = [boundary, current];
      }
    }, [searchBar.isOpen]);

    useEffect(() {
      scrollController.addListener(onScrolling);
      return () {
        scrollController.removeListener(onScrolling);
      };
    }, [searchBar.isOpen]);

    // Reset delta when there's no scrollable widget attached.
    // Scheduling work from `build` itself produces a callback per rebuild,
    // which previously fired every keystroke. The post-frame check now lives
    // in a `useEffect` keyed on `delta` so it only schedules when the value
    // could plausibly need resetting.
    useEffect(() {
      if (delta.value.first == 0 && delta.value.last == 0) return null;
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        if (scrollController.hasClients) return;
        if (delta.value.reduce((a, b) => a + b) != 0) {
          delta.value = [0, 0];
        }
      });
      return null;
    }, [delta.value]);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: context.theme.scaffoldBackgroundColor.withValues(
            alpha: context.isLightThemed
                ? isBlurAllowed
                      ? 0.7
                      : 0.92
                : isBlurAllowed
                ? 0.85
                : 0.97,
          ),
          border: Border(
            top: BorderSide(color: context.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (searchBar.isOpen) const _OptionBar(),
              Container(
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.all(Radius.circular(DesignTokens.radiusLg)),
                ),
                margin: const EdgeInsets.fromLTRB(DesignTokens.spacingMd, DesignTokens.spacingMd - DesignTokens.spacingXs, DesignTokens.spacingMd, DesignTokens.spacingMd - DesignTokens.spacingXs),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        const _LeadingButton(),
                        if (!searchBar.isOpen)
                          Positioned(right: 8, child: _RatingIndicator()),
                      ],
                    ),
                    const Expanded(child: _SearchField()),
                    if (!searchBar.isOpen)
                      _TrailingButton(
                        collapsed: collapsed,
                        scrollController: scrollController,
                      ),
                    if (searchBar.isOpen &&
                        searchBar.value != searchBar.initial)
                      _Button(
                        onTap: searchBar.reset,
                        child: const Icon(Icons.rotate_left),
                      ),
                    if (searchBar.isOpen)
                      _Button(
                        onTap: searchBar.clear,
                        child: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double innerHeight = kBottomNavigationBarHeight + 12;
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

    return RepaintBoundary(
      child: TextField(
        autofocus: searchBar.isOpen,
        canRequestFocus: searchBar.isOpen,
        enableIMEPersonalizedLearning: !imeIncognito,
        controller: searchBar.textEditingController,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: searchBar.value.isEmpty
              ? context.t.searchHint(serverName: server.name)
              : searchBar.value,
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
      ),
    );
  }
}

class _OptionBar extends StatelessWidget {
  const _OptionBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(DesignTokens.spacingMd + DesignTokens.spacingXs, DesignTokens.spacingMd - DesignTokens.spacingXs, DesignTokens.spacingMd + DesignTokens.spacingXs, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [_RatingButton()],
      ),
    );
  }
}

class _RatingButton extends ConsumerWidget {
  const _RatingButton();

  String rateDesc(BuildContext context, BooruRating rating) {
    final desc = rating.describe(context);
    return desc.isEmpty ? context.t.rating.all : desc;
  }

  Future<BooruRating?> selectRating(BuildContext context, BooruRating current) {
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
                      title: Text(rateDesc(context, e)),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref.watch(
      serverSettingStateProvider.select((it) => it.searchRating),
    );
    final label = '${context.t.rating.title}: ${rateDesc(context, rating)}';

    return OutlinedButton(
      onPressed: () async {
        final selected = await selectRating(context, rating);
        if (selected != null) {
          await ref
              .read(serverSettingStateProvider.notifier)
              .setRating(selected);
        }
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs, horizontal: DesignTokens.spacingMd),
        minimumSize: const Size(1, 1),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          width: 1,
          color: context.colorScheme.surfaceContainerHighest,
        ),
        elevation: 0,
      ),
      child: Text(
        label.toLowerCase(),
        style: TextStyle(color: context.colorScheme.onSurface),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.onTap, this.child});

  final void Function() onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd - DesignTokens.spacingXs, 6, DesignTokens.spacingMd - DesignTokens.spacingXs, 6),
        child: child,
      ),
    );
  }
}

class _LeadingButton extends ConsumerWidget {
  const _LeadingButton();

  Future<void> _showServerSelector(
    BuildContext context,
    WidgetRef ref,
    String currentServerId,
  ) async {
    final servers = ref.read(serverStateProvider).toList();
    final session = ref.read(searchSessionProvider);
    final enableBlur = ref.read(uiSettingStateProvider.select((s) => s.blur));

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final backgroundColor = context.theme.scaffoldBackgroundColor;
        final content = Container(
          decoration: BoxDecoration(
            color: enableBlur
                ? backgroundColor.withValues(alpha: 0.85)
                : backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(DesignTokens.spacingMd + DesignTokens.spacingXs, DesignTokens.spacingSm, DesignTokens.spacingMd + DesignTokens.spacingXs, DesignTokens.spacingMd),
                  child: Text(
                    context.t.servers.select,
                    style: context.theme.textTheme.titleMedium,
                  ),
                ),
                // Server list
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: servers.length,
                    itemBuilder: (context, index) {
                      final server = servers[index];
                      final isSelected = server.id == currentServerId;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                        leading: Favicon(
                          url: server.homepage,
                          shape: BoxShape.circle,
                          iconSize: 24,
                        ),
                        title: Text(server.name),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: context.colorScheme.primary,
                              )
                            : null,
                        selected: isSelected,
                        selectedTileColor: context.colorScheme.primary
                            .withAlpha(context.isLightThemed ? 30 : 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        onTap: () => Navigator.of(context).pop(server.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );

        if (!enableBlur) return content;

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: content,
          ),
        );
      },
    );

    if (selected != null && selected != currentServerId && context.mounted) {
      unawaited(
        context.router.push(
          HomeRoute(session: session.copyWith(serverId: selected)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final server = ref.watch(serverStateProvider).getById(session.serverId);
    final searchBar = ref.watch(searchBarControllerProvider(session));

    return _Button(
      onTap: () {
        if (searchBar.isOpen) {
          searchBar.close();
        } else {
          _showServerSelector(context, ref, session.serverId);
        }
      },
      child: searchBar.isOpen
          ? const Icon(Icons.arrow_back_rounded)
          : Favicon(
              key: ValueKey(server.homepage),
              url: server.homepage,
              iconSize: 18,
            ),
    );
  }
}

class _RatingIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref.watch(
      serverSettingStateProvider.select((it) => it.searchRating),
    );

    String letter = 's';
    switch (rating) {
      case BooruRating.questionable:
        letter = 'q';
        break;
      case BooruRating.sensitive:
        letter = 'v';
        break;
      case BooruRating.explicit:
        letter = 'e';
        break;
      default:
        break;
    }
    final colorScheme = Theme.of(context).colorScheme;
    Color color;
    switch (rating) {
      case BooruRating.safe:
        color = colorScheme.tertiary;
        break;
      case BooruRating.questionable:
        color = colorScheme.outline;
        break;
      case BooruRating.sensitive:
        color = colorScheme.secondary;
        break;
      case BooruRating.explicit:
        color = colorScheme.error;
        break;
      default:
        color = colorScheme.tertiary;
        break;
    }
    return Visibility(
      visible: rating != BooruRating.all,
      child: Container(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        padding: const EdgeInsets.all(4),
        child: Text(
          letter,
          style: TextStyle(fontSize: 10, color: colorScheme.onPrimary),
        ),
      ),
    );
  }
}

class _TrailingButton extends ConsumerWidget {
  const _TrailingButton({this.collapsed = false, this.scrollController});

  final bool collapsed;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = context.iconTheme.size ?? 24;
    final grid = ref.watch(uiSettingStateProvider.select((ui) => ui.grid));

    backToTop() {
      scrollController?.animateTo(
        0,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    }

    return _Button(
      onTap: collapsed
          ? backToTop
          : ref.read(uiSettingStateProvider.notifier).cycleGrid,
      child: SizedBox(
        width: size,
        height: size,
        child: collapsed
            ? const Icon(Icons.arrow_upward_rounded)
            : Icon(key: ValueKey(grid), Icons.grid_view, size: 20),
      ),
    );
  }
}
