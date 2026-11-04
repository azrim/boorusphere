import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:flutter/material.dart';

/// The checkbox row of the block language, so one opt-in is laid out the same
/// way in a server form as in a settings sheet.
///
/// A [CheckboxListTile] carries no inset of its own here: the column it sits in
/// has already paid for the gutter — a form pads its fields, a sheet pads its
/// body — and a second inset on the row is what put this tick 12 dp out of line
/// with the field above it. Two server pages wrote the same row out in full and
/// a settings sheet wrote a third version with the box on the other edge, which
/// is how the same control came to mean two different alignments.
class BlockCheckboxTile extends StatelessWidget {
  const BlockCheckboxTile({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    required this.onChanged,
  });

  final bool value;
  final String title;
  final String? subtitle;

  /// Called with the state the reader asked for, never with the null a tap on
  /// an indeterminate box could answer with.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      // The box keeps the trailing edge, the way a switch row carries its
      // switch, so every toggle in the app answers from the same column.
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(title),
      subtitle: subtitle == null ? null : RowSubtitle(Text(subtitle)),
      onChanged: (isChecked) {
        if (isChecked != null) onChanged(isChecked);
      },
    );
  }
}
