import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// The observer the root navigator reports route changes to.
///
/// A top-level instance rather than a provider: the post viewer is handed the
/// container of the page that opened it, so a provider read on both sides can
/// resolve to different containers (and therefore different observers, only
/// one of which the navigator knows about).
final RouteObserver<Route<dynamic>> appRouteObserver =
    RouteObserver<Route<dynamic>>();

/// Whether [route] is the one the user is looking at.
///
/// Flutter keeps a non-opaque route (the post viewer) running underneath an
/// opaque one: the framework only mutes its tickers. That is enough for
/// painting, but it leaves the covered page believing it is still on screen:
/// its videos keep playing and it keeps claiming process-wide resources. This
/// mirrors the navigator's push/pop-next callbacks into a rebuild so the owner
/// can release them.
///
/// The initial value comes from the route itself, because a page can be built
/// while another route already covers it; no callback is coming for that.
bool useRouteVisible(
  ModalRoute<dynamic>? route,
  RouteObserver<Route<dynamic>> observer,
) {
  final visible = useState(route?.isCurrent ?? true);

  useEffect(() {
    if (route == null) return null;

    final subscription = _RouteVisibilitySubscription(
      onShown: () => visible.value = true,
      onHidden: () => visible.value = false,
    );
    observer.subscribe(subscription, route);

    if (visible.value != route.isCurrent) {
      visible.value = route.isCurrent;
    }

    return () => observer.unsubscribe(subscription);
  }, [route, observer]);

  return visible.value;
}

class _RouteVisibilitySubscription extends RouteAware {
  _RouteVisibilitySubscription({required this.onShown, required this.onHidden});

  final VoidCallback onShown;
  final VoidCallback onHidden;

  @override
  void didPushNext() => onHidden();

  @override
  void didPopNext() => onShown();
}
