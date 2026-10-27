import 'package:boorusphere/presentation/widgets/section_label.dart';
import 'package:flutter/material.dart';

/// Drawer section label with an optional count and a trailing action.
///
/// The drawer keeps its own name for the row so a reader of the drawer code
/// sees a drawer concept, but the spacing and type come from [SectionHeading]
/// like every other section in the app.
class DrawerSectionHeader extends StatelessWidget {
  const DrawerSectionHeader(this.label, {super.key, this.count, this.action});

  final String label;
  final int? count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SectionHeading(label, count: count, action: action);
  }
}
