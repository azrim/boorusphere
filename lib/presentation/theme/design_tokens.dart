import 'package:flutter/material.dart';

/// Design tokens for spacing, border radius, and motion.
class DesignTokens {
  DesignTokens._();

  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // Inset for a row that sits inside a grouped surface.
  static const double spacingCardInset = 12.0;

  // Border Radius
  static const double radiusSm = 4.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusFull = 999.0;

  // Sizes
  static const double iconChipSize = 32.0;
  static const double iconInline = 18.0;
  static const double brandMarkSize = 40.0;
  static const double brandLogoSize = 24.0;
  static const double controlHeightMin = 48.0;
  static const double drawerMaxWidth = 410.0;
  static const double drawerContentPeek = 84.0;

  // Elevation. Four levels, each one a claim about what a surface is doing:
  // a block that groups rows, chrome that floats over the content, an overlay
  // that owns the screen, and a dialog that stops everything.
  static const double elevationRaised = 1.0;
  static const double elevationFloating = 3.0;
  static const double elevationOverlay = 6.0;
  static const double elevationModal = 12.0;

  /// The colour every shadow is drawn with: the scheme's own shadow pulled a
  /// step towards the page, so a shadow reads as a darker part of the surface
  /// instead of a grey smudge laid on top of it.
  static Color shadowColor(ColorScheme scheme) {
    final tint = Color.lerp(scheme.shadow, scheme.surface, 0.18)!;
    final alpha = scheme.brightness == Brightness.dark ? 0.62 : 0.22;
    return tint.withValues(alpha: alpha);
  }

  // Motion
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);

  /// How long a message stays up: long enough to read a sentence, short
  /// enough that it does not sit on top of the next action.
  static const Duration durationSnackbar = Duration(seconds: 2);

  // Curves
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveDecelerate = Curves.easeOut;
  static const Curve curveAccelerate = Curves.easeIn;
}
