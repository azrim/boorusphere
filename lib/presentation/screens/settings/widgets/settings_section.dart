import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/section_label.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:flutter/material.dart';

/// Rounded block of setting rows without a label, for rows that name
/// themselves.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SectionSurface(
      children: [
        ListTileTheme(
          data: ListTileThemeData(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingCardInset,
            ),
            minVerticalPadding: DesignTokens.spacingSm,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

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
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spacingXs,
            DesignTokens.spacingLg,
            DesignTokens.spacingXs,
            DesignTokens.spacingSm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SectionLabel(title),
          ),
        ),
        if (children.isNotEmpty) SettingsGroup(children: children),
      ],
    );
  }
}

/// Label, optional current value, and the slider underneath. The value sits
/// beside the label instead of floating at the edge of the row, and the slider
/// keeps the full width so the label never has to wrap.
class SettingsSliderTile extends StatelessWidget {
  const SettingsSliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    this.valueLabel,
    this.helper,
    this.enabled = true,
    this.onChanged,
    this.onChangeEnd,
  });

  final String title;
  final String? valueLabel;
  final String? helper;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool enabled;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final valueLabel = this.valueLabel;
    final helper = this.helper;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingCardInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
              if (valueLabel != null)
                Text(
                  valueLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? onChangeEnd : null,
          ),
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
              child: Text(
                helper,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
