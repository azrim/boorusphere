import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Flat field: no fill, no box, just a hairline underline, so a form reads as
/// rows inside a [SectionSurface] instead of slabs drawn on top of it.
InputDecoration flatFieldDecoration(BuildContext context, {String? label}) {
  final scheme = context.colorScheme;
  final labelStyle = context.theme.textTheme.labelSmall?.copyWith(
    color: scheme.onSurfaceVariant,
  );
  final hairline = UnderlineInputBorder(
    borderSide: BorderSide(color: scheme.outlineVariant),
  );

  return InputDecoration(
    labelText: label,
    labelStyle: labelStyle,
    floatingLabelStyle: labelStyle,
    isDense: true,
    contentPadding: const EdgeInsets.only(
      top: DesignTokens.spacingMd,
      bottom: DesignTokens.spacingSm,
    ),
    border: hairline,
    enabledBorder: hairline,
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: scheme.primary),
    ),
  );
}
