import 'package:async/async.dart';
import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/screens/home/drawer/home_drawer.dart';
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

@RoutePage()
class HomePage extends HookConsumerWidget {
  const HomePage({super.key, this.session});

  final SearchSession? session;

  Rect _timelineBoundary(BuildContext context) {
    final bottom =
        MediaQuery.paddingOf(context).bottom + HomeSearchBar.innerHeight;
    return Rect.fromLTRB(0, 0, 0, bottom);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedServerId =
        ref.read(serverSettingStateProvider.select((it) => it.lastActiveId));
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
      return null;
    }, const []);

    return ProviderScope(
      overrides: [
        searchSessionProvider.overrideWith((ref) => session),
        pageStateProvider.overrideWith(
          () => PageState(session: session),
        ),
        suggestionStateProvider.overrideWith(
          () => SuggestionState(session: session),
        ),
        timelineControllerProvider.overrideWith(
          (ref) => TimelineController(
            scrollController: AutoScrollController(
              viewportBoundaryGetter: () => _timelineBoundary(context),
            ),
            onLoadMore: () => ref.read(pageStateProvider.notifier).loadMore(),
          ),
        ),
      ],
      child: const _Home(),
    );
  }
}

class _Home extends HookConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final searchBar = ref.watch(searchBarControllerProvider(session));
    final scaffoldKey = useMemoized(GlobalKey<ScaffoldState>.new, const []);
    final drawerWidth = MediaQuery.sizeOf(context).width.clamp(0.0, 410.0) - 84;
    final allowPop = useState(false);
    const maybePopTimeout = Duration(seconds: 1);
    final maybePopTimer = useMemoized(
      () => RestartableTimer(maybePopTimeout, () {
        if (context.mounted) allowPop.value = false;
      }),
    );

    return Scaffold(
      key: scaffoldKey,
      extendBody: true,
      drawer: HomeDrawer(maxWidth: drawerWidth),
      drawerEdgeDragWidth: searchBar.isOpen ? 0 : 24,
      body: StyledOverlayRegion(
        child: PopScope(
          canPop:
              (allowPop.value || context.router.canPop()) && !searchBar.isOpen,
          onPopInvokedWithResult: (didPop, _) async {
            if (searchBar.isOpen) {
              maybePopTimer.cancel();
              context.scaffoldMessenger.hideCurrentSnackBar();
              searchBar.close();
              return;
            }

            if (!allowPop.value && !context.router.canPop()) {
              allowPop.value = true;
              context.scaffoldMessenger.showSnackBar(SnackBar(
                content: Text(context.t.retryPopBack),
                duration: maybePopTimeout,
              ));
              maybePopTimer.cancel();
              maybePopTimer.reset();
            }
          },
          child: const HomeContent(),
        ),
      ),
    );
  }
}
