import 'package:boorusphere/presentation/screens/home/drawer/drawer_brand_header.dart';
import 'package:boorusphere/presentation/screens/home/drawer/drawer_footer.dart';
import 'package:boorusphere/presentation/screens/home/drawer/drawer_library_section.dart';
import 'package:boorusphere/presentation/screens/home/drawer/drawer_preferences_section.dart';
import 'package:boorusphere/presentation/screens/home/drawer/drawer_server_section.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// Navigation drawer for the home screen.
///
/// A brand header, a scrollable body of grouped sections (servers, library,
/// preferences), and a pinned footer carrying exit and the version readout.
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
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacingMd,
                  0,
                  DesignTokens.spacingMd,
                  DesignTokens.spacingMd,
                ),
                children: const [
                  DrawerServerSection(),
                  DrawerLibrarySection(),
                  DrawerPreferencesSection(),
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
