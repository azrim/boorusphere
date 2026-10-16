import 'package:boorusphere/presentation/screens/home/drawer/drawer_brand_header.dart';
import 'package:boorusphere/presentation/screens/home/drawer/drawer_footer.dart';
import 'package:boorusphere/presentation/screens/home/drawer/drawer_library_section.dart';
import 'package:boorusphere/presentation/screens/home/drawer/drawer_preferences_section.dart';
import 'package:boorusphere/presentation/screens/home/drawer/drawer_server_section.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Navigation drawer for the home screen.
///
/// A brand header, a scrollable body (servers, library, preferences), and a
/// pinned footer carrying the version and update status.
class HomeDrawer extends StatelessWidget {
  const HomeDrawer({super.key, required this.maxWidth});

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: maxWidth,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(DesignTokens.radiusXl),
          bottomRight: Radius.circular(DesignTokens.radiusXl),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const HomeDrawerHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingLg,
                ),
                children: [
                  const DrawerServerSection(),
                  const DrawerLibrarySection(),
                  Divider(
                    height: DesignTokens.spacingLg,
                    color: context.colorScheme.outlineVariant,
                  ),
                  const DrawerPreferencesSection(),
                  const SizedBox(height: DesignTokens.spacingMd),
                ],
              ),
            ),
            const DrawerFooter(),
          ],
        ),
      ),
    );
  }
}
