import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:flutter/material.dart';

/// Small-caps label with a hairline underline that hugs the text.
///
/// Shared by the drawer and the settings pages so both read as one system.
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
        ? Semantics(header: true, container: true, child: text)
        : text;
  }
}
