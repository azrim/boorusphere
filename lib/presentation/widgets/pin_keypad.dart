import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';

/// The diameter of one keypad key: a 64 dp circle, comfortably over the 48 dp
/// minimum target while three keys and their gaps still fit a narrow screen.
const double _kKeySize = 64.0;

/// The gap between keys in a row and between rows.
const double _kKeyGap = DesignTokens.spacingMd;

/// The diameter of one filled PIN dot and the gap the row keeps between them.
const double _kDotSize = 12.0;
const double _kDotGap = DesignTokens.spacingMd;

/// The keys of the pad, in reading order; the empty string is the blank cell
/// beside the zero and `back` is the backspace key.
const _kRows = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['', '0', 'back'],
];

/// A PIN entry pad with the app's own keys, so the gate never depends on the
/// system keyboard.
///
/// Keys are filled circles on the block tone with a hairline edge, the same
/// vocabulary a section block uses, and the press is the Material ink of any
/// other control. The pad reports digit and backspace taps; the caller owns
/// the value, the dots and the error line.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  /// Called with the digit on a number key.
  final ValueChanged<String> onDigit;

  /// Called when the backspace key is pressed.
  final VoidCallback onBackspace;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final flat = AppSurfacePolicy.of(context).flat;

    Widget key(Widget child, {VoidCallback? onTap, String? semanticLabel}) {
      return Semantics(
        label: semanticLabel,
        button: true,
        child: Material(
          // Midnight keeps the page tone and lets the hairline do the
          // separating, like every other block.
          color: flat ? scheme.surface : scheme.surfaceContainerHigh,
          shape: const CircleBorder(
            side: BorderSide(color: Colors.transparent),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: _kKeySize,
              height: _kKeySize,
              child: Center(child: child),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, row) in _kRows.indexed) ...[
          if (index > 0) const SizedBox(height: _kKeyGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (i, value) in row.indexed) ...[
                if (i > 0) const SizedBox(width: _kKeyGap),
                switch (value) {
                  '' => const SizedBox(width: _kKeySize, height: _kKeySize),
                  'back' => key(
                    Icon(
                      Icons.backspace_outlined,
                      size: DesignTokens.iconAction + 4,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: onBackspace,
                    semanticLabel: t.appLock.backspace,
                  ),
                  _ => key(
                    Text(
                      value,
                      style: context.theme.textTheme.titleLarge?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    onTap: () => onDigit(value),
                    semanticLabel: value,
                  ),
                },
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// The row of filled dots standing in for the digits typed so far.
///
/// [length] is how many are in, [maxLength] how many fit; the empty slots stay
/// as hollow rings so the reader can see how far from full the entry is.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.maxLength,
    this.error = false,
  });

  final int length;
  final int maxLength;

  /// Draws every dot in the error color, so a wrong entry reads before the
  /// message under it does.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final fill = error ? scheme.error : scheme.onSurface;
    final empty = error ? scheme.error : scheme.outlineVariant;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < maxLength; i++) ...[
          if (i > 0) const SizedBox(width: _kDotGap),
          AnimatedContainer(
            duration: DesignTokens.durationFast,
            curve: DesignTokens.curveStandard,
            width: _kDotSize,
            height: _kDotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < length ? fill : Colors.transparent,
              border: Border.all(color: empty),
            ),
          ),
        ],
      ],
    );
  }
}
