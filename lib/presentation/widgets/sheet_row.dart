import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:flutter/material.dart';

const _rowPadding = EdgeInsets.symmetric(
  horizontal: DesignTokens.spacingMd,
  vertical: DesignTokens.spacingCardInset,
);

/// The label role a sheet uses inside a panel: the small caps line that names
/// what a value or a group is.
TextStyle? sheetLabelStyle(BuildContext context) {
  return context.theme.textTheme.labelSmall?.copyWith(
    color: context.colorScheme.onSurfaceVariant,
    fontWeight: FontWeight.w600,
    letterSpacing: 1,
  );
}

/// The value role: body size with tabular figures, so scores, counts and
/// dimensions line up down a panel instead of drifting with each digit.
TextStyle? sheetValueStyle(BuildContext context) {
  return context.theme.textTheme.bodyMedium?.copyWith(
    color: context.colorScheme.onSurface,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Stacks panel rows and rules them: one hairline between rows, none after the
/// last, so a panel ends on the sheet's own edge.
class SheetPanel extends StatelessWidget {
  const SheetPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              // The rules start where the labels do, so a panel reads as a
              // table instead of a stack of full-width bars.
              indent: DesignTokens.spacingMd,
              endIndent: DesignTokens.spacingMd,
              color: context.colorScheme.outlineVariant,
            ),
        ],
      ],
    );
  }
}

/// One row of a sheet panel: an optional leading slot, a title with an optional
/// supporting line, an optional trailing slot.
///
/// The same row carries a choice, a toggle and a piece of information, so every
/// panel in the app reads as one ruled list.
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.title,
    this.detail,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
  });

  final String title;

  /// A second line in the supporting size, for the option's own explanation.
  final String? detail;

  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Marks the row as the current value: it takes a container tint, and the
  /// trailing slot is where the caller puts the check.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final textTheme = context.theme.textTheme;

    final row = Container(
      constraints: const BoxConstraints(
        minHeight: DesignTokens.controlHeightMin,
      ),
      padding: _rowPadding,
      color: selected ? scheme.surfaceContainerHighest : null,
      child: Row(
        children: [
          if (leading case final leading?) ...[
            leading,
            const SizedBox(width: DesignTokens.spacingCardInset),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
                ),
                if (detail case final detail?) ...[
                  const SizedBox(height: DesignTokens.spacingXs),
                  Text(
                    detail,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing case final trailing?) ...[
            const SizedBox(width: DesignTokens.spacingSm),
            trailing,
          ],
        ],
      ),
    );

    if (onTap == null) return row;

    return InkWell(onTap: onTap, child: row);
  }
}

/// A label and its value on one line: the fact rows a details panel is made of.
class SheetFactRow extends StatelessWidget {
  const SheetFactRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: DesignTokens.controlHeightMin,
      ),
      padding: _rowPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label.toUpperLocale(context),
              style: sheetLabelStyle(context),
            ),
          ),
          const SizedBox(width: DesignTokens.spacingMd),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sheetValueStyle(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row that points somewhere: the label, an optional readout, the address
/// itself, and the control that copies it.
class SheetLinkRow extends StatelessWidget {
  const SheetLinkRow({
    super.key,
    required this.label,
    required this.url,
    this.detail,
    this.onOpen,
    this.onCopy,
  });

  final String label;
  final String url;

  /// A readout for the target, such as its size and format.
  final String? detail;

  final VoidCallback? onOpen;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final textTheme = context.theme.textTheme;

    final body = Container(
      constraints: const BoxConstraints(
        minHeight: DesignTokens.controlHeightMin,
      ),
      padding: _rowPadding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperLocale(context),
                  style: sheetLabelStyle(context),
                ),
                if (detail case final detail?) ...[
                  const SizedBox(height: DesignTokens.spacingXs + 2),
                  Text(detail, style: sheetValueStyle(context)),
                ],
                const SizedBox(height: DesignTokens.spacingXs + 2),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: scheme.primary),
                ),
              ],
            ),
          ),
          if (onCopy case final onCopy?) ...[
            const SizedBox(width: DesignTokens.spacingSm),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: context.t.actionTag.copy,
              onPressed: onCopy,
            ),
          ],
        ],
      ),
    );

    if (onOpen == null) return body;

    return InkWell(onTap: onOpen, child: body);
  }
}
