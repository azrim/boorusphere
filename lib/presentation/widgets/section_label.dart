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
        style: context.theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
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
  const SectionHeading(this.label, {super.key, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingXs,
        DesignTokens.spacingLg,
        DesignTokens.spacingXs,
        DesignTokens.spacingSm,
      ),
      child: Row(
        children: [
          SectionLabel(label),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}
