import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// A supporting line inside a block, in the row's own vocabulary.
///
/// The block already owns its outer inset, so this adds only the row inset:
/// the note starts where a row title starts and ends where a row title ends.
/// The gap above and below is the same gap a row keeps between its title and
/// its supporting line, so a note reads as part of the group instead of as a
/// warning parked next to it.
class InBlockNote extends StatelessWidget {
  const InBlockNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingCardInset,
        vertical: DesignTokens.spacingSm,
      ),
      child: Text(text, style: AppTextRoles.of(context).rowSupporting),
    );
  }
}
