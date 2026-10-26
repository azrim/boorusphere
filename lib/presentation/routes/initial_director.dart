import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/provider/app_boot_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class InitialDirectorPage extends HookConsumerWidget {
  const InitialDirectorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booted = ref.watch(appBootStateProvider);
    useEffect(() {
      // The boot adopts a default server on a fresh install, so the active id
      // is only known once it has finished; reading it earlier opens the
      // timeline on a session that resolves to no server at all.
      if (!booted) return null;
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        if (!context.mounted) return;
        final lastActiveId = ref.read(serverSettingStateProvider).lastActiveId;
        context.router.replace(
          HomeRoute(session: SearchSession(serverId: lastActiveId)),
        );
      });
      return null;
    }, [booted]);

    return const Material();
  }
}
