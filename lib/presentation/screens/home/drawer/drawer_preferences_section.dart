import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_section_header.dart';
import 'package:boorusphere/presentation/screens/home/drawer/widgets/drawer_tile.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Preferences and destructive actions: settings, reset to default, and exit.
class DrawerPreferencesSection extends ConsumerWidget {
  const DrawerPreferencesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DrawerSectionHeader(context.t.sidebar.preferences),
        DrawerTile(
          icon: Icons.settings_outlined,
          label: context.t.settings.title,
          trailing: Icon(
            Icons.chevron_right,
            size: 18,
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
        DrawerTile(
          icon: Icons.exit_to_app,
          label: context.t.exit,
          danger: true,
          onTap: () => _showExitDialog(context),
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

void _showExitDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t.exit),
      content: Text(context.t.exitConfirmation),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.cancel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            SystemNavigator.pop();
          },
          child: Text(context.t.exit),
        ),
      ],
    ),
  );
}
