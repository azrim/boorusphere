import 'package:async/async.dart';
import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/screens/home/drawer/home_drawer.dart';
import 'package:boorusphere/presentation/screens/home/drawer/home_drawer_controller.dart';
import 'package:boorusphere/presentation/screens/home/home_content.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/screens/home/whats_new_bottom_sheet.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/styled_overlay_region.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:vector_math/vector_math_64.dart';

@RoutePage()
class HomePage extends HookConsumerWidget {
  const HomePage({super.key, this.session});

  final SearchSession? session;

  Rect _timelineBoundary(BuildContext context) {
    final bottom =
        context.mediaQuery.padding.bottom + HomeSearchBar.innerHeight;
    return Rect.fromLTRB(0, 0, 0, bottom);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedServerId = ref.read(
      serverSettingStateProvider.select((it) => it.lastActiveId),
    );
    final session = this.session ?? SearchSession(serverId: savedServerId);
    final envRepo = ref.read(envRepoProvider);
    final appStateRepo = ref.read(appStateRepoProvider);

    useEffect(() {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) async {
        if (envRepo.appVersion.isNewerThan(appStateRepo.version)) {
          await appStateRepo.storeVersion(envRepo.appVersion);
          if (context.mounted) {
            WhatsNewBottomSheet.show(context);
          }
        }
      });
    }, []);

    return Scaffold(
      extendBody: true,
      body: StyledOverlayRegion(
        child: ProviderScope(
          overrides: [
            searchSessionProvider.overrideWith((ref) => session),
            pageStateProvider.overrideWith(() => PageState(session: session)),
            suggestionStateProvider.overrideWith(
              () => SuggestionState(session: session),
            ),
            searchBarControllerProvider.overrideWith(
              (ref) => SearchBarController(ref, session: session),
            ),
            homeDrawerControllerProvider.overrideWith(
              (ref) => HomeDrawerController(),
            ),
            timelineControllerProvider.overrideWith(
              (ref) => TimelineController(
                scrollController: AutoScrollController(
                  viewportBoundaryGetter: () => _timelineBoundary(context),
                ),
                onLoadMore: () =>
                    ref.read(pageStateProvider.notifier).loadMore(),
              ),
            ),
          ],
          child: _Home(),
        ),
      ),
    );
  }
}

class _Home extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch booleans via select so this widget only rebuilds when isOpen
    // actually transitions, not on every keystroke (search bar) or
    // animation tick (drawer).
    final isSearchOpen = ref.watch(
      searchBarControllerProvider.select((c) => c.isOpen),
    );
    final isDrawerOpen = ref.watch(
      homeDrawerControllerProvider.select((c) => c.isOpen),
    );
    // Read the controller instances without subscribing for action callbacks.
    final searchBar = ref.read(searchBarControllerProvider);
    final drawer = ref.read(homeDrawerControllerProvider);
    final atHomeScreen = !isDrawerOpen && !isSearchOpen;
    final allowPop = useState(false);
    const maybePopTimeout = Duration(seconds: 1);
    final maybePopTimer = useMemoized(
      () => RestartableTimer(maybePopTimeout, () {
        if (context.mounted) allowPop.value = false;
      }),
    );
    clearMaybePop() {
      allowPop.value = false;
      maybePopTimer.cancel();
    }

    return PopScope(
      canPop:
          (allowPop.value || context.router.canPop()) &&
          !isDrawerOpen &&
          !isSearchOpen,
      onPopInvokedWithResult: (didPop, _) async {
        if (isDrawerOpen || isSearchOpen) {
          maybePopTimer.cancel();
          context.scaffoldMessenger.hideCurrentSnackBar();
          if (isDrawerOpen) {
            await drawer.close();
          } else if (isSearchOpen) {
            searchBar.close();
          }
          return;
        }

        if (!allowPop.value && !context.router.canPop()) {
          allowPop.value = true;
          context.scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(context.t.retryPopBack),
              duration: maybePopTimeout,
            ),
          );
          maybePopTimer.cancel();
          maybePopTimer.reset();
        }
      },
      child: _SlidableContainer(
        edgeDragWidth: atHomeScreen ? context.mediaQuery.size.width : 0,
        onSlideStatus: (status) {
          if (status != AnimationStatus.dismissed) {
            clearMaybePop();
            context.scaffoldMessenger.hideCurrentSnackBar();
          }
        },
        body: const HomeContent(),
      ),
    );
  }
}

class _SlidableContainer extends HookConsumerWidget {
  const _SlidableContainer({
    required this.body,
    this.edgeDragWidth,
    this.onSlideStatus,
  });

  final Widget body;
  final double? edgeDragWidth;
  final void Function(AnimationStatus open)? onSlideStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animator = useAnimationController(
      duration: const Duration(milliseconds: 300),
    );
    final tween = CurveTween(curve: Curves.easeInOutSine).animate(animator);
    final maxDrawerWidth =
        (context.mediaQuery.size.width).clamp(0.0, 410.0) - 84;
    final canBeDragged = useState(true);

    final animationListener = useCallback(() {
      if (animator.isAnimating) return;

      onSlideStatus?.call(animator.status);
    }, []);

    useEffect(() {
      animator.addListener(animationListener);
      return () {
        animator.removeListener(animationListener);
      };
    }, []);

    // Read once: the controller instance is stable for the lifetime of the
    // ProviderScope override. Avoid `ref.watch` here so this widget does not
    // rebuild on drawer state changes — the AnimatedBuilder below already
    // observes the AnimationController directly.
    final drawer = ref.read(homeDrawerControllerProvider);
    useEffect(() {
      drawer.setAnimator(animator);
      return null;
    }, const []);

    return GestureDetector(
      onHorizontalDragStart: (details) {
        final dragWidth = edgeDragWidth ?? context.mediaQuery.size.width / 2;
        final dx = details.globalPosition.dx;
        final isOpen = animator.isDismissed && dx < dragWidth;
        final isClose = animator.isCompleted && dx > dragWidth;
        // ignore when gesture started on the edge to avoid conflict
        // with system back gesture
        if (dx < 24) {
          canBeDragged.value = false;
          return;
        }

        canBeDragged.value = isOpen || isClose;
      },
      onHorizontalDragUpdate: (details) {
        if (!canBeDragged.value) return;

        final delta = details.primaryDelta;
        if (delta == null) return;

        animator.value += delta / maxDrawerWidth;
      },
      onHorizontalDragEnd: (details) async {
        if (animator.isCompleted || animator.isDismissed) return;

        if (details.velocity.pixelsPerSecond.dx.abs() >= 365) {
          final visualVelocity =
              details.velocity.pixelsPerSecond.dx /
              context.mediaQuery.size.width;

          await animator.fling(velocity: visualVelocity);
        } else if (animator.value < 0.5) {
          await animator.reverse();
        } else {
          await animator.forward();
        }
      },
      child: AnimatedBuilder(
        animation: tween,
        child: Material(
          color: context.theme.scaffoldBackgroundColor,
          child: body,
        ),
        builder: (context, child) {
          final slide = maxDrawerWidth * tween.value;
          return Stack(
            children: [
              Transform(
                transform: Matrix4.identity()
                  ..setTranslationRaw(
                    (1 - tween.value) * (maxDrawerWidth / 2),
                    0,
                    0,
                  )
                  ..translateByVector3(Vector3(slide - maxDrawerWidth, 0, 0)),
                alignment: Alignment.centerLeft,
                child: HomeDrawer(maxWidth: maxDrawerWidth),
              ),
              Transform.translate(
                offset: Offset(slide, 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: animator.isCompleted ? drawer.close : null,
                  child: IgnorePointer(
                    ignoring: animator.isCompleted,
                    child: child,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
