import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// Supporting line of a row, with the 8 dp gap a [ListTile] does not add
/// itself, so every row in a grouped surface keeps the same title-to-subtitle
/// rhythm.
class RowSubtitle extends StatelessWidget {
  const RowSubtitle(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
      child: child,
    );
  }
}
