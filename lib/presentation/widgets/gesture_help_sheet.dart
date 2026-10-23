import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:flutter/material.dart';

/// Reference sheet for the gestures and the rating letters the app uses.
/// Gesture Settings configures them; this only explains what they are.
Future<void> showGestureHelp(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => const _GestureHelpSheet(),
  );
}

class _GestureHelpSheet extends StatelessWidget {
  const _GestureHelpSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final rows = <(IconData, String)>[
      (Icons.touch_app_outlined, context.t.help.tap),
      (Icons.pan_tool_alt_outlined, context.t.help.longPress),
      (Icons.zoom_in, context.t.help.doubleTap),
      (Icons.keyboard_arrow_up_rounded, context.t.help.swipeUp),
      (Icons.keyboard_arrow_down_rounded, context.t.help.swipeDown),
    ];

    Widget row(IconData icon, String label) {
      return ListTile(
        leading: Icon(
          icon,
          size: DesignTokens.iconInline,
          color: scheme.onSurfaceVariant,
        ),
        title: Text(label),
        dense: true,
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          DesignTokens.spacingSm,
          DesignTokens.spacingMd,
          DesignTokens.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t.help.title,
              style: context.theme.textTheme.titleMedium,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            SectionSurface(
              children: [
                for (final (icon, label) in rows) row(icon, label),
                row(Icons.star_outline, context.t.help.rating),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
