import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_badge.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_section_header.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_tile.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Library shortcuts: downloads, favorites, and blocked tags with live counts.
class DrawerLibrarySection extends ConsumerWidget {
  const DrawerLibrarySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final downloads = ref.watch(downloadEntryStateProvider).length;
    final favorites = ref.watch(favoritePostStateProvider).length;
    final blockedTags = ref.watch(tagsBlockerStateProvider).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DrawerSectionHeader(context.t.sidebar.library),
        SectionSurface(
          children: [
            DrawerTile(
              icon: Icons.cloud_download_outlined,
              label: context.t.downloads.title,
              trailing: downloads > 0 ? DrawerBadge('$downloads') : null,
              onTap: () {
                Navigator.of(context).pop();
                context.router.push(DownloadsRoute(session: session));
              },
            ),
            DrawerTile(
              icon: Icons.favorite_border,
              label: context.t.favorites.title,
              trailing: favorites > 0 ? DrawerBadge('$favorites') : null,
              onTap: () {
                Navigator.of(context).pop();
                context.router.push(FavoritesRoute(session: session));
              },
            ),
            DrawerTile(
              icon: Icons.block,
              label: context.t.tagsBlocker.title,
              trailing: blockedTags > 0 ? DrawerBadge('$blockedTags') : null,
              onTap: () {
                Navigator.of(context).pop();
                context.router.push(const TagsBlockerRoute());
              },
            ),
          ],
        ),
      ],
    );
  }
}
