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
];

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

      for (final palette in _curated) {
        expect(
          paletteColorsFor(palette, Brightness.light),
          isNotNull,
          reason: '${palette.name} has no light palette',
        );
        expect(
          paletteColorsFor(palette, Brightness.dark),
          isNotNull,
          reason: '${palette.name} has no dark palette',
        );
      }
    });

    test('each palette paints its own page instead of a shared ramp', () {
      for (final brightness in Brightness.values) {
        final backgrounds = _curated
            .map((it) => paletteColorsFor(it, brightness)!.background)
            .toSet();
        final panels = _curated
            .map((it) => paletteColorsFor(it, brightness)!.panel)
            .toSet();

        expect(
          backgrounds.length,
          _curated.length,
          reason: 'two ${brightness.name} palettes share a background',
        );
        expect(
          panels.length,
          _curated.length,
          reason: 'two ${brightness.name} palettes share a panel',
        );
      }
    });

    test('body and secondary text stay readable on both surfaces', () {
      for (final palette in _curated) {
        for (final brightness in Brightness.values) {
          final colors = paletteColorsFor(palette, brightness)!;
          final where = '${palette.name}/${brightness.name}';

          expect(
            _contrast(colors.text, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: 'text on background, $where',
          );
          expect(
            _contrast(colors.muted, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: 'muted on background, $where',
          );
          expect(
            _contrast(colors.text, colors.panel),
            greaterThanOrEqualTo(4.5),
            reason: 'text on panel, $where',
          );
          expect(
            _contrast(colors.muted, colors.panel),
            greaterThanOrEqualTo(4.5),
            reason: 'muted on panel, $where',
          );
        }
      }
    });

    test('accents stay visible against the page', () {
      for (final palette in _curated) {
        for (final brightness in Brightness.values) {
          final colors = paletteColorsFor(palette, brightness)!;
          final where = '${palette.name}/${brightness.name}';

          for (final accent in [
            colors.primary,
            colors.secondary,
            colors.tertiary,
            colors.error,
          ]) {
            expect(
              _contrast(accent, colors.background),
              greaterThanOrEqualTo(3.0),
              reason: 'accent $accent on background, $where',
            );
          }
        }
      }
    });

    test('the scheme carries the palette through every surface role', () {
      for (final palette in _curated) {
        for (final brightness in Brightness.values) {
          final colors = paletteColorsFor(palette, brightness)!;
          final scheme = colors.toScheme(brightness);

          expect(scheme.brightness, brightness);
          expect(scheme.surface, colors.background);
          expect(scheme.onSurface, colors.text);
          expect(scheme.onSurfaceVariant, colors.muted);
          expect(scheme.primary, colors.primary);
          expect(scheme.outline, colors.border);
          expect(
            scheme.surfaceContainerHighest,
            isNot(scheme.surface),
            reason: '${palette.name}/${brightness.name} has no card step',
          );
        }
      }
    });

    test('a picked palette reaches the built theme unchanged', () {
      final dracula = paletteColorsFor(ColorPalette.dracula, Brightness.dark)!;
      final theme = AppThemeData.from(colorPalette: ColorPalette.dracula).night;

      expect(theme.colorScheme.surface, dracula.background);
      expect(theme.scaffoldBackgroundColor, dracula.background);
      expect(theme.colorScheme.primary, dracula.primary);

      final light = paletteColorsFor(ColorPalette.dracula, Brightness.light)!;
      expect(
        AppThemeData.from(
          colorPalette: ColorPalette.dracula,
        ).day.colorScheme.surface,
        light.background,
      );
    });

    test('midnight keeps the palette accents on black', () {
      final theme = AppThemeData.from(colorPalette: ColorPalette.nord).midnight;
      final nord = paletteColorsFor(ColorPalette.nord, Brightness.dark)!;

      expect(theme.colorScheme.surface, Colors.black);
      expect(theme.colorScheme.primary, nord.primary);
    });
  });
}
