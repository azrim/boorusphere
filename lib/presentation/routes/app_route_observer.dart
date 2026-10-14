import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AppRouteObserver extends AutoRouterObserver {
  AppRouteObserver(this.ref);

  final WidgetRef ref;

  SearchSession? _getSession(Route? route) {
    // Only a handful of routes carry a [SearchSession] in their arguments.
    // Match on those argument types explicitly so routes without a session
    // (e.g. ServerAddRoute, SettingsRoute) don't trigger a spurious lookup.
    final args = route?.settings.arguments;
    return switch (args) {
      HomeRouteArgs(:final session) => session,
      DownloadsRouteArgs(:final session) => session,
      FavoritesRouteArgs(:final session) => session,
      _ => null,
    };
  }

  void _setLastActiveServer(String id) {
    final lastActive = ref.read(serverSettingStateProvider).lastActiveId;
    if (id.isEmpty || lastActive == id) return;

    ref.read(serverSettingStateProvider.notifier).setLastActiveId(id);
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    final session = _getSession(route);

    if (session != null) {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        _setLastActiveServer(session.serverId);
      });
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    final session = _getSession(previousRoute);

    if (session != null) {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        _setLastActiveServer(session.serverId);
      });
    }
  }
}
