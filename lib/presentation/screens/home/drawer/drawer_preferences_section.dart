import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_section_header.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_tile.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Preferences: settings and reset to default. Exiting the app lives in the
/// footer, next to the version readout.
class DrawerPreferencesSection extends ConsumerWidget {
  const DrawerPreferencesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DrawerSectionHeader(context.t.sidebar.preferences),
        SectionSurface(
          children: [
            DrawerTile(
              icon: Icons.settings_outlined,
              label: context.t.settings.title,
              trailing: Icon(
                Icons.chevron_right,
                size: DesignTokens.iconInline,
                color: context.colorScheme.onSurfaceVariant,
              ),
              onTap: () {
                Navigator.of(context).pop();
                context.router.push(const SettingsRoute());
              },
            ),
            DrawerTile(
              icon: Icons.restore,
              label: context.t.resetToDefault,
              onTap: () => _showResetDialog(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}

void _showResetDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t.resetToDefault),
      icon: const Icon(Icons.restore),
      content: Text(context.t.servers.resetWarning),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            ref.read(serverStateProvider.notifier).reset();
          },
          child: Text(context.t.reset),
        ),
      ],
    ),
  );
}
