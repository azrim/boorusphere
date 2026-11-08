import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/theme/app_actions.dart';
import 'package:flutter/material.dart';

/// Asks before an action that cannot be undone.
///
/// The confirm carries the error colour instead of a filled primary button, so
/// a destructive verb is never the most attractive control in the dialog. Every
/// screen asks with this dialog, so the answer reads the same whether it comes
/// from the drawer, a page or a sheet.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.delete_outline,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final actions = AppActionRoles.of(context);
      return AlertDialog(
        icon: Icon(icon, color: actions.error),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: actions.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
