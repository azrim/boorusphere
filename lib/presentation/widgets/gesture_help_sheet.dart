import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/sheet_row.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:flutter/material.dart';

/// Reference sheet for the gestures and the rating letters the app uses.
/// Gesture Settings configures them; this only explains what they are.
Future<void> showGestureHelp(BuildContext context) {
  return showSheet<void>(
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
      (Icons.star_outline_rounded, context.t.help.rating),
    ];

    return SheetShell(
      title: context.t.help.title,
      child: SingleChildScrollView(
        child: SheetPanel(
          children: [
            for (final (icon, label) in rows)
              SheetRow(
                title: label,
                leading: Icon(
                  icon,
                  size: DesignTokens.iconInline,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
