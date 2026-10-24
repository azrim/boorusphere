import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Opens a settings sheet: the container every settings row that only asks for
/// a value uses, instead of pushing a route or floating an [AlertDialog].
Future<T?> showSettingsSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: builder,
  );
}

/// The chrome shared by every settings sheet: title on top, body in the middle,
/// and an optional pinned footer for the sheet's primary action.
class SheetShell extends StatelessWidget {
  const SheetShell({
    super.key,
    required this.title,
    required this.child,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: Padding(
        // A text field inside the sheet has to clear the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacingLg,
                0,
                DesignTokens.spacingLg,
                DesignTokens.spacingSm,
              ),
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
            Flexible(child: child),
            if (footer case final footer?) ...[
              const SizedBox(height: DesignTokens.spacingSm),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacingLg,
                  0,
                  DesignTokens.spacingLg,
                  DesignTokens.spacingMd,
                ),
                child: footer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
  return showSettingsSheet<Choice<T>>(
    context: context,
    builder: (context) => SheetShell(
      title: title,
      // Flat rows with no dividers, the same block language the settings
      // pages use; the sheet border is the block border.
      child: ListTileTheme(
        data: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingCardInset,
          ),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
          itemCount: choices.length,
          itemBuilder: (context, index) {
            final choice = choices[index];
            final isSelected = choice.value == selected;

            return ListTile(
              leading: choice.leading,
              title: Text(choice.label),
              subtitle: choice.detail == null ? null : Text(choice.detail!),
              selected: isSelected,
              trailing: isSelected
                  ? Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(context, choice),
            );
          },
        ),
      ),
    ),
  );
}

/// Edits one short value, such as a chat id or a token.
Future<String?> showTextSheet({
  required BuildContext context,
  required String title,
  required String saveLabel,
  required String cancelLabel,
  String? hint,
  String? initialValue,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
}) {
  return showSettingsSheet<String>(
    context: context,
    builder: (context) => _TextSheet(
      title: title,
      saveLabel: saveLabel,
      cancelLabel: cancelLabel,
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
    required this.cancelLabel,
    this.hint,
    this.initialValue,
    this.keyboardType,
    this.inputFormatters,
  });

  final String title;
  final String saveLabel;
  final String cancelLabel;
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
      footer: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(cancelLabel),
            ),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(elevation: 0),
              onPressed: save,
              child: Text(saveLabel),
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingLg),
        child: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => save(),
          decoration: InputDecoration(hintText: hint),
        ),
      ),
    );
  }
}
