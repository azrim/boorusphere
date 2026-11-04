import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// The scrolling list every block-based page is built from.
///
/// The rhythm belongs to the page, not to its blocks: the side gutter is the
/// one a block already expects, there is no top inset because a section heading
/// brings its own, and the bottom run-out is the same gap a heading keeps above
/// itself, so the last block clears the edge of the window on every page
/// instead of on the ones whose author remembered to add it.
///
/// A block with no heading of its own is separated from the top by a leading
/// `SizedBox(height: DesignTokens.spacingLg)`, the gap a heading would have
/// made, rather than a padding the list cannot know about.
class SectionedList extends StatelessWidget {
  const SectionedList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        0,
        DesignTokens.spacingMd,
        DesignTokens.spacingLg,
      ),
      children: children,
    );
  }
}
