import 'dart:math' as math;

import 'package:boorusphere/presentation/provider/app_theme.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/theme/app_media_chrome.dart';
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

/// The tone a viewer actually shows a glyph: the role painted over the stage,
/// because chrome never sits on an empty page, it sits on black behind art.
Color _over(Color role, Color stage) => Color.alphaBlend(role, stage);

void main() {
  group('AppMediaChrome', () {
    for (final palette in ColorPalette.values) {
      for (final which in ['day', 'night', 'midnight']) {
        final theme = switch (which) {
          'day' => AppThemeData.from(colorPalette: palette).day,
          'night' => AppThemeData.from(colorPalette: palette).night,
          _ => AppThemeData.from(colorPalette: palette).midnight,
        };
        final chrome = theme.extension<AppMediaChrome>();
        final where = '${palette.name}/$which';

        test('$where hands the artwork chrome a light glyph on a dark bed', () {
          // The claim the hard-coded white and black used to make by fiat: a
          // control drawn over the picture is lighter than the picture's bed,
          // whichever polarity the app theme has.
          expect(chrome, isNotNull, reason: 'no role set on the theme, $where');
          expect(
            _luminance(chrome!.foreground),
            greaterThan(_luminance(chrome.stage)),
            reason: 'the glyph sinks into the stage, $where',
          );
          expect(
            _luminance(chrome.scrim),
            lessThan(_luminance(chrome.foreground)),
            reason: 'the scrim is not the dark side, $where',
          );
        });

        test('$where keeps every on-image label readable', () {
          expect(
            _contrast(chrome!.foreground, _over(chrome.scrim, chrome.stage)),
            greaterThanOrEqualTo(4.5),
            reason: 'app bar and toolbox glyphs over the scrim, $where',
          );
          expect(
            _contrast(chrome.foreground, _over(chrome.plate, chrome.stage)),
            greaterThanOrEqualTo(4.5),
            reason: 'timeline overlay labels on their plate, $where',
          );
          expect(
            _contrast(chrome.foreground, chrome.stage),
            greaterThanOrEqualTo(4.5),
            reason: 'glyphs letterboxed straight onto the stage, $where',
          );
        });

        test('$where leaves a disabled control visibly dimmer', () {
          final bed = _over(chrome!.scrim, chrome.stage);
          expect(
            _contrast(chrome.foregroundDisabled, bed),
            greaterThanOrEqualTo(3.0),
            reason: 'a dimmed button must still read as a button, $where',
          );
          // Alpha, not the channel, is what dims a role, so the comparison has
          // to be made where the pixel actually lands: over the scrim.
          expect(
            _luminance(_over(chrome.foregroundDisabled, bed)),
            lessThan(_luminance(_over(chrome.foreground, bed))),
            reason: 'disabled reads as inactive, $where',
          );
        });
      }
    }

    test('midnight paints the viewer stage the page black', () {
      // The midnight rule is pure black, and the viewer is where that rule
      // matters most, so its scrim is built from the same black rather than
      // from the night tint the day and night themes use.
      final midnight = AppThemeData.from().midnight;
      final night = AppThemeData.from().night;

      expect(midnight.extension<AppMediaChrome>()!.stage, Colors.black);
      expect(
        midnight.extension<AppMediaChrome>()!.scrim.a,
        night.extension<AppMediaChrome>()!.scrim.a,
        reason: 'midnight changed the scrim weight, not only its black',
      );
    });

    test('a curated palette reaches the chrome through its own neutrals', () {
      // The role set is derived, not hard-coded, so a palette that owns its
      // neutrals owns its viewer too.
      final theme = AppThemeData.from(colorPalette: ColorPalette.dracula).night;
      final chrome = theme.extension<AppMediaChrome>()!;

      expect(chrome.foreground, theme.colorScheme.onSurface);
      expect(chrome.stage, theme.colorScheme.surface);
    });

    test('without the extension a widget still resolves sensible roles', () {
      // Tests and any third-party theme entry build a bare MaterialApp; the
      // fallback has to give the same relationship rather than nothing.
      final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
      expect(AppMediaChrome.from(scheme).foreground.a, 1.0);
      expect(
        _luminance(AppMediaChrome.from(scheme).foreground),
        greaterThan(_luminance(AppMediaChrome.from(scheme).stage)),
      );
    });
  });
}
