import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:flutter/material.dart';

/// Small-caps label with a hairline underline that hugs the text.
///
/// Shared by the drawer, the settings pages, and the server forms so they all
/// read as one system.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key, this.header = true});

  final String label;

  /// Marks the label as a heading so screen readers can jump between sections.
  final bool header;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final text = Container(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingXs + 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Text(
        label.toUpperLocale(context),
        style: AppTextRoles.of(context).sectionLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return header
        ? Semantics(
            header: true,
            // Sections sit directly under the screen title, so they are the
            // first level of the document.
            headingLevel: 2,
            container: true,
            child: text,
          )
        : text;
  }
}

/// A [SectionLabel] with the spacing a section needs above and below it, and
/// an optional trailing action on the same line.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.label, {super.key, this.action, this.count});

  final String label;
  final Widget? action;

  /// How many items the section holds, shown beside the label.
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingXs,
        DesignTokens.spacingLg,
        DesignTokens.spacingXs,
        DesignTokens.spacingSm,
      ),
      // The label yields before the action does: at a large font scale a long
      // title has to ellipsize instead of pushing the action off the row.
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(child: SectionLabel(label)),
                if (count != null) ...[
                  const SizedBox(width: DesignTokens.spacingSm),
                  Text('$count', style: AppTextRoles.of(context).sectionLabel),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: DesignTokens.spacingSm),
            action!,
          ],
        ],
      ),
    );
  }
}
