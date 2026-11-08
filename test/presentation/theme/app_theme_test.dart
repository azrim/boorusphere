import 'dart:math' as math;

import 'package:boorusphere/presentation/provider/app_theme.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/theme/app_actions.dart';
import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

BorderSide _sideOf(ShapeBorder? shape) {
  if (shape is OutlinedBorder) return shape.side;
  fail('expected an outlined border, got $shape');
}

void main() {
  group('AppThemeData', () {
    test('two identical builds produce equal themes', () {
      for (final palette in ColorPalette.values) {
        final first = AppThemeData.from(colorPalette: palette);
        final second = AppThemeData.from(colorPalette: palette);
        final where = palette.name;

        // ThemeData compares its extensions by value and restarts the theme
        // cross-fade when they differ, so an unrelated root rebuild must not
        // hand it a different set.
        expect(first.day, second.day, reason: 'day themes differ, $where');
        expect(
          first.night,
          second.night,
          reason: 'night themes differ, $where',
        );
        expect(
          first.midnight,
          second.midnight,
          reason: 'midnight themes differ, $where',
        );
      }
    });

    test('action roles read on every block of every built theme', () {
      for (final palette in ColorPalette.values) {
        final themes = AppThemeData.from(colorPalette: palette);
        final variants = [
          ('day', themes.day),
          ('night', themes.night),
          ('midnight', themes.midnight),
        ];

        for (final (mode, theme) in variants) {
          final where = '${palette.name}/$mode';
          final actions = theme.extension<AppActionRoles>();
          final scheme = theme.colorScheme;
          expect(actions, isNotNull, reason: 'no action roles, $where');
          final tones = {
            'page': scheme.surface,
            'panel': scheme.surfaceContainer,
            'block': scheme.surfaceContainerHigh,
            'selection': scheme.surfaceContainerHighest,
          };

          for (final MapEntry(key: name, value: tone) in tones.entries) {
            expect(
              _contrast(actions!.primary, tone),
              greaterThanOrEqualTo(4.5),
              reason: 'primary on the $name, $where',
            );
            expect(
              _contrast(actions.error, tone),
              greaterThanOrEqualTo(4.5),
              reason: 'error on the $name, $where',
            );
          }
        }
      }
    });

    test('only midnight flattens the surfaces', () {
      final themes = AppThemeData.from(colorPalette: ColorPalette.dracula);

      expect(themes.day.extension<AppSurfacePolicy>()!.flat, isFalse);
      expect(themes.night.extension<AppSurfacePolicy>()!.flat, isFalse);
      expect(themes.midnight.extension<AppSurfacePolicy>()!.flat, isTrue);
    });

    test('day and night drop the box outlines, midnight keeps them', () {
      for (final palette in ColorPalette.values) {
        final themes = AppThemeData.from(colorPalette: palette);
        final where = palette.name;

        // Flat-first: a raised tone and a shadow are the separation. A box
        // outline around the same surface was a second edge for one job, and
        // on a curated palette it was often the brightest line on screen.
        for (final (mode, theme) in [
          ('day', themes.day),
          ('night', themes.night),
        ]) {
          expect(
            _sideOf(theme.popupMenuTheme.shape),
            BorderSide.none,
            reason: 'menu outline, $where/$mode',
          );
          expect(
            _sideOf(theme.bottomSheetTheme.shape),
            BorderSide.none,
            reason: 'sheet outline, $where/$mode',
          );
          expect(
            _sideOf(theme.snackBarTheme.shape),
            BorderSide.none,
            reason: 'toast outline, $where/$mode',
          );
          expect(
            _sideOf(theme.dialogTheme.shape),
            BorderSide.none,
            reason: 'dialog outline, $where/$mode',
          );
        }

        // On black there is no tone step and no shadow, so the hairline is
        // the only thing that keeps an overlay from dissolving into the page.
        final midnight = themes.midnight;
        for (final (name, side) in [
          ('menu', _sideOf(midnight.popupMenuTheme.shape)),
          ('sheet', _sideOf(midnight.bottomSheetTheme.shape)),
          ('toast', _sideOf(midnight.snackBarTheme.shape)),
          ('dialog', _sideOf(midnight.dialogTheme.shape)),
        ]) {
          expect(side, isNot(BorderSide.none), reason: 'no $name line, $where');
          expect(side.color, midnight.colorScheme.outlineVariant);
        }
      }
    });
  });
}
