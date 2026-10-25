import 'dart:math' as math;

import 'package:boorusphere/presentation/provider/app_theme.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/theme/color_palettes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The palettes that carry their own colours instead of a seed.
const _curated = [
  ColorPalette.dracula,
  ColorPalette.catpuccin,
  ColorPalette.nord,
  ColorPalette.solarized,
  ColorPalette.gruvbox,
  ColorPalette.oneDark,
  ColorPalette.monokai,
  ColorPalette.github,
  ColorPalette.tokyoNight,
  ColorPalette.ayu,
];

/// Themes that ship one polarity only. Their day scheme is generated from the
/// accent instead of pretending to be a light variant.
const _darkOnly = [
  ColorPalette.nord,
  ColorPalette.monokai,
  ColorPalette.solarized,
  ColorPalette.gruvbox,
];

/// Every (palette, brightness) pair that has curated colours.
Iterable<(ColorPalette, Brightness)> get _variants sync* {
  for (final palette in _curated) {
    for (final brightness in Brightness.values) {
      if (brightness == Brightness.light && _darkOnly.contains(palette)) {
        continue;
      }
      yield (palette, brightness);
    }
  }
}

double _luminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Color palettes', () {
    test('only the generated palettes have no curated colours', () {
      expect(paletteColorsFor(ColorPalette.system, Brightness.dark), isNull);
      expect(
        paletteColorsFor(ColorPalette.materialYou, Brightness.dark),
        isNull,
      );

      for (final (palette, brightness) in _variants) {
        expect(
          paletteColorsFor(palette, brightness),
          isNotNull,
          reason: '${palette.name} has no ${brightness.name} palette',
        );
      }

      for (final palette in _darkOnly) {
        expect(
          paletteColorsFor(palette, Brightness.light),
          isNull,
          reason: '${palette.name} only ships a dark variant',
        );
      }
    });

    test('each palette paints its own page instead of a shared ramp', () {
      for (final brightness in Brightness.values) {
        final palettes = _variants
            .where((it) => it.$2 == brightness)
            .map((it) => it.$1)
            .toList();
        // Two themes may both sit on a near-white page; what has to be their
        // own is the ramp, so the pair is what gets compared.
        final ramps = palettes.map((it) {
          final colors = paletteColorsFor(it, brightness)!;
          return '${colors.background.toARGB32()}-${colors.container.toARGB32()}';
        }).toSet();

        expect(
          ramps.length,
          palettes.length,
          reason: 'two ${brightness.name} palettes share a ramp',
        );
      }
    });

    test('the elevated steps move away from the page in order', () {
      for (final (palette, brightness) in _variants) {
        final colors = paletteColorsFor(palette, brightness)!;
        final where = '${palette.name}/${brightness.name}';
        final ramp = [
          colors.container,
          colors.containerHigh,
          colors.containerHighest,
        ];

        for (var i = 1; i < ramp.length; i++) {
          expect(
            _contrast(ramp[i], colors.background),
            greaterThan(_contrast(ramp[i - 1], colors.background)),
            reason: 'step $i does not lift off the page, $where',
          );
        }
        expect(
          colors.containerLow,
          isNot(colors.containerHighest),
          reason: 'the low and highest steps collapse, $where',
        );
      }
    });

    test('body and secondary text stay readable on both surfaces', () {
      for (final (palette, brightness) in _variants) {
        final colors = paletteColorsFor(palette, brightness)!;
        final where = '${palette.name}/${brightness.name}';

        final scheme = colors.toScheme(brightness);
        expect(
          _contrast(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'shipped text on background, $where',
        );
        expect(
          _contrast(scheme.onSurface, scheme.surfaceContainer),
          greaterThanOrEqualTo(4.5),
          reason: 'shipped text on panel, $where',
        );
        expect(
          _contrast(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'shipped muted on background, $where',
        );
        expect(
          _contrast(scheme.onSurfaceVariant, scheme.surfaceContainer),
          greaterThanOrEqualTo(4.5),
          reason: 'shipped muted on panel, $where',
        );
      }
    });

    test('every shipped accent reads against the page', () {
      for (final (palette, brightness) in _variants) {
        final colors = paletteColorsFor(palette, brightness)!;
        final scheme = colors.toScheme(brightness);
        final where = '${palette.name}/${brightness.name}';

        for (final accent in [
          scheme.primary,
          scheme.secondary,
          scheme.tertiary,
          scheme.error,
        ]) {
          expect(
            _contrast(accent, scheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: 'accent $accent on the page, $where',
          );
        }
      }
    });

    test('the scheme carries the palette through every surface role', () {
      for (final (palette, brightness) in _variants) {
        final colors = paletteColorsFor(palette, brightness)!;
        final scheme = colors.toScheme(brightness);
        final where = '${palette.name}/${brightness.name}';

        expect(scheme.brightness, brightness);
        expect(scheme.surface, colors.background);
        expect(scheme.surfaceContainerLow, colors.containerLow);
        expect(scheme.surfaceContainer, colors.container);
        expect(scheme.surfaceContainerHigh, colors.containerHigh);
        expect(scheme.surfaceContainerHighest, colors.containerHighest);
        expect(scheme.outline, colors.line, reason: 'strong line, $where');
        expect(
          scheme.outlineVariant,
          colors.border,
          reason: 'soft hairline, $where',
        );
        expect(
          scheme.outline,
          isNot(scheme.outlineVariant),
          reason: 'one line tone for both roles, $where',
        );
      }
    });

    test('a picked palette reaches the built theme unchanged', () {
      final dracula = paletteColorsFor(ColorPalette.dracula, Brightness.dark)!;
      final theme = AppThemeData.from(colorPalette: ColorPalette.dracula).night;

      expect(theme.colorScheme.surface, dracula.background);
      expect(theme.scaffoldBackgroundColor, dracula.background);
      expect(theme.colorScheme.primary, dracula.primary);

      final alucard = paletteColorsFor(ColorPalette.dracula, Brightness.light)!;
      expect(
        AppThemeData.from(
          colorPalette: ColorPalette.dracula,
        ).day.colorScheme.surface,
        alucard.background,
      );
    });

    test('a dark-only theme seeds its day scheme from its accent', () {
      final nord = paletteColorsFor(ColorPalette.nord, Brightness.dark)!;
      final theme = AppThemeData.from(colorPalette: ColorPalette.nord);

      expect(theme.night.colorScheme.surface, nord.background);
      expect(theme.day.colorScheme.surface, isNot(nord.background));
      expect(theme.day.colorScheme.brightness, Brightness.light);
    });

    test('midnight keeps the palette accents on black', () {
      final theme = AppThemeData.from(colorPalette: ColorPalette.nord).midnight;
      final nord = paletteColorsFor(ColorPalette.nord, Brightness.dark)!;

      expect(theme.colorScheme.surface, Colors.black);
      expect(theme.colorScheme.primary, nord.primary);
    });
  });
}
