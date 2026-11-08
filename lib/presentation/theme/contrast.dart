import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.x contrast ratio: 1 for two identical tones, 21 for black on white.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Black or white, whichever carries more contrast on [color].
///
/// A brightness estimate is the right tool for polarity but not for a label:
/// it has a dead band where it picks white while black is the only tone above
/// the floor. Comparing the two ratios never lands in that band.
Color readableOn(Color color) {
  return contrastRatio(Colors.white, color) >=
          contrastRatio(Colors.black, color)
      ? Colors.white
      : Colors.black;
}

/// Walks [color] toward its readable pole, one small step at a time, until it
/// clears [floor] on every tone in [surfaces].
///
/// A ramp is ordered by lightness, so the tone closest to the colour is one of
/// its ends; moving away from it only raises contrast on the tones beyond. The
/// hue never changes, only lightness, and the walk stops the step it clears
/// the floor.
Color readableOnSurfaces(
  Color color,
  Iterable<Color> surfaces, {
  double floor = 4.5,
  double step = 0.06,
}) {
  var result = color;
  for (var i = 0; i < 24; i++) {
    final worst = _worstSurface(result, surfaces);
    if (contrastRatio(result, worst) >= floor) break;
    result = Color.lerp(result, readableOn(worst), step)!;
  }
  return result;
}

Color _worstSurface(Color color, Iterable<Color> surfaces) {
  var worst = surfaces.first;
  for (final surface in surfaces.skip(1)) {
    if (contrastRatio(color, surface) < contrastRatio(color, worst)) {
      worst = surface;
    }
  }
  return worst;
}
