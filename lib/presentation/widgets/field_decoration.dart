import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Flat field: no fill, no box, just a hairline underline, so a form reads as
/// rows inside a [SectionSurface] instead of slabs drawn on top of it.
///
/// The label sits above the field in the small muted role in every state, so a
/// label never takes the slot the value belongs to and an empty field still
/// reads as an empty field. The value keeps the 16 sp body size, an example
/// goes in [hint], and the error line drops to the 12 sp supporting size.
InputDecoration flatFieldDecoration(
  BuildContext context, {
  String? label,
  String? hint,
}) {
  final scheme = context.colorScheme;
  final textTheme = context.theme.textTheme;
  final labelStyle = textTheme.labelSmall?.copyWith(
    color: scheme.onSurfaceVariant,
  );
  final hairline = UnderlineInputBorder(
    borderSide: BorderSide(color: scheme.outlineVariant),
  );

  return InputDecoration(
    labelText: label,
    labelStyle: labelStyle,
    floatingLabelStyle: labelStyle,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    hintText: hint,
    hintStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
    errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
    isDense: true,
    contentPadding: const EdgeInsets.only(
      top: DesignTokens.spacingCardInset,
      bottom: DesignTokens.spacingSm,
    ),
    border: hairline,
    enabledBorder: hairline,
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: scheme.primary),
    ),
  );
}
