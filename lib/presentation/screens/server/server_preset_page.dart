import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class ServerPresetPage extends ConsumerWidget {
  const ServerPresetPage({super.key, this.onReturned});

  final void Function(Server newData)? onReturned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the bundled presets belong here: saved servers in the box carry
    // credentials, aliases and migrated fields that make them unequal to the
    // preset they started from, which would list the same board twice.
    final presets = ref.watch(
      serverRepoProvider.select((it) => it.defaults.values),
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.t.servers.select)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          // The presets are one block of rows, the same language the drawer,
          // settings and server pages use. `dense` is dropped with it: the row
          // scale the rest of the app runs at is the one this list needs too.
          children: [
            TileGroup(
              children: [
                for (final it in presets)
                  ListTile(
                    title: Text(it.name),
                    subtitle: RowSubtitle(Text(it.homepage)),
                    leading: Favicon(url: it.homepage),
                    onTap: () {
                      onReturned?.call(it);
                      context.router.maybePop();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
