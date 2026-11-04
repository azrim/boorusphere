import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/section_label.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
import 'package:flutter/material.dart';

/// Section label followed by its grouped rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.children = const <Widget>[],
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(title),
        if (children.isNotEmpty) TileGroup(children: children),
      ],
    );
  }
}

/// Label, the value it stands at, and the slider underneath. The value sits
/// beside the label instead of floating at the edge of the row, and the slider
/// keeps the full width so the label never has to wrap.
///
/// The row owns the number under the finger. A caller keeping its own draft was
/// wrong twice over: the copy never heard about a value written elsewhere — a
/// restored archive, another screen — and the slider then asserted on a number
/// outside its own steps; and writing on every reported step put a value into
/// storage for every pixel the thumb moved. So the draft lives here, the label
/// and the helper line are read from it, and the caller is asked once, when the
/// drag ends.
class SettingsSliderTile extends StatefulWidget {
  const SettingsSliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChangeEnd,
    this.labelFor,
    this.helperFor,
    this.enabled = true,
  });

  final String title;

  /// The stored value: where the row sits when nobody is dragging it, and where
  /// a drag that never lands returns to.
  final double value;
  final double min;
  final double max;
  final int divisions;

  /// The number beside the title, read from the value the row shows. Without it
  /// the row has no readout.
  final String Function(double value)? labelFor;

  /// The line under the slider, from the same value, so it keeps agreeing with
  /// the thumb while the finger is still moving.
  final String Function(double value)? helperFor;
  final bool enabled;

  /// The value the drag ended on, once per drag.
  final ValueChanged<double> onChangeEnd;

  @override
  State<SettingsSliderTile> createState() => _SettingsSliderTileState();
}

class _SettingsSliderTileState extends State<SettingsSliderTile> {
  /// The value under the finger, or null when nobody is dragging. It ends with
  /// the drag it belongs to, so an outside change is never overwritten by a
  /// stale copy of a number.
  double? _draft;

  double get _shown => _draft ?? widget.value;

  void _preview(double value) {
    setState(() => _draft = value);
  }

  void _end(double value) {
    widget.onChangeEnd(value);
    setState(() => _draft = null);
  }

  @override
  Widget build(BuildContext context) {
    final roles = AppTextRoles.of(context);
    final shown = _shown;
    final label = widget.labelFor?.call(shown);
    final helper = widget.helperFor?.call(shown);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingCardInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.title, style: roles.rowTitle)),
              // Tabular figures: the readout sits in the same place every
              // frame of a drag, so it must not change width as digits change.
              if (label != null) Text(label, style: roles.numeric),
            ],
          ),
          Slider(
            value: shown,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: label,
            // The slider reads its own state from the callbacks: no handler is
            // what "disabled" looks like.
            onChanged: widget.enabled ? _preview : null,
            onChangeEnd: widget.enabled ? _end : null,
          ),
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
              child: Text(helper, style: roles.rowSupporting),
            ),
        ],
      ),
    );
  }
}
