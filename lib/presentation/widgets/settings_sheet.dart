import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/field_decoration.dart';
import 'package:boorusphere/presentation/widgets/sheet_row.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// One row of a [showChoiceSheet].
class Choice<T> {
  const Choice({
    required this.value,
    required this.label,
    this.detail,
    this.leading,
  });

  final T value;
  final String label;

  /// A second line, for the option's own explanation or alias.
  final String? detail;

  final Widget? leading;
}

/// Asks for one value out of a short list.
///
/// Returns the chosen [Choice] — not the bare value — so a choice whose value
/// is null stays distinguishable from a dismissed sheet.
Future<Choice<T>?> showChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required List<Choice<T>> choices,
  required T? selected,
}) {
  return showSheet<Choice<T>>(
    context: context,
    builder: (context) {
      final scheme = context.colorScheme;

      return SheetShell(
        title: title,
        child: SingleChildScrollView(
          child: SheetPanel(
            children: [
              for (final choice in choices)
                SheetRow(
                  title: choice.label,
                  detail: choice.detail,
                  leading: choice.leading,
                  selected: choice.value == selected,
                  trailing: choice.value == selected
                      ? Icon(
                          Icons.check_rounded,
                          size: DesignTokens.iconAction,
                          color: scheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, choice),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Edits one short value, such as a chat id or a token.
Future<String?> showTextSheet({
  required BuildContext context,
  required String title,
  required String saveLabel,
  String? hint,
  String? initialValue,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
}) {
  return showSheet<String>(
    context: context,
    builder: (context) => _TextSheet(
      title: title,
      saveLabel: saveLabel,
      hint: hint,
      initialValue: initialValue,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
    ),
  );
}

class _TextSheet extends HookWidget {
  const _TextSheet({
    required this.title,
    required this.saveLabel,
    this.hint,
    this.initialValue,
    this.keyboardType,
    this.inputFormatters,
  });

  final String title;
  final String saveLabel;
  final String? hint;
  final String? initialValue;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: initialValue);

    void save() => Navigator.pop(context, controller.text);

    return SheetShell(
      title: title,
      // One action. The shell already carries a close control and the
      // backdrop dismisses, so a Cancel button was a third way out taking half
      // the width of the only action that matters.
      footer: ElevatedButton(onPressed: save, child: Text(saveLabel)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          DesignTokens.spacingSm,
          DesignTokens.spacingMd,
          0,
        ),
        child: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => save(),
          decoration: flatFieldDecoration(context, hint: hint),
        ),
      ),
    );
  }
}
