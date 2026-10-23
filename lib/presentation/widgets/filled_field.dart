import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// Borderless filled field, so a form reads as content inside a
/// [SectionSurface] instead of a box drawn on top of it.
InputDecoration filledFieldDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: context.colorScheme.surfaceContainerHighest,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: DesignTokens.spacingCardInset,
      vertical: DesignTokens.spacingCardInset + 2,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      borderSide: BorderSide.none,
    ),
  );
}
