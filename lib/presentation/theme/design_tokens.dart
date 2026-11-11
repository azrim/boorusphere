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

  /// The glyph inside a 48 dp icon button: one step up from inline, so an
  /// action reads as tappable without competing with the row it sits in.
  static const double iconAction = 20.0;
  static const double brandMarkSize = 40.0;
  static const double brandLogoSize = 24.0;
  static const double controlHeightMin = 48.0;
  static const double drawerMaxWidth = 410.0;
  static const double drawerContentPeek = 84.0;

  /// The measure a sheet's rows stop growing at. The sheet keeps its
  /// full-bleed surface; past this width the content is centred, so a tablet
  /// gets margins instead of a table stretched across the screen.
  static const double sheetContentMaxWidth = 640.0;

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

  /// The opacity-only leg. What a movement keeps of itself once the platform
  /// asks for reduced motion, and the whole of a change that never travelled:
  /// long enough to read as a change, too short to feel like waiting.
  static const Duration durationFade = Duration(milliseconds: 120);

  /// How long a message stays up: long enough to read a sentence, short
  /// enough that it does not sit on top of the next action.
  static const Duration durationSnackbar = Duration(seconds: 2);

  /// The window an undo gets. It is longer than an info toast because the
  /// action it reverses has already happened; a newer message still replaces
  /// it, so a stale undo never hides the next result.
  static const Duration durationUndo = Duration(seconds: 8);

  // Curves
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveDecelerate = Curves.easeOut;
  static const Curve curveAccelerate = Curves.easeIn;

  /// A surface that is already on screen and is being moved aside by another
  /// one arriving over it. It starts and ends at rest, so it reads as being
  /// pushed rather than as leaving: a departure curve here would make the
  /// covered page look like it was dismissing itself.
  static const Curve curveShift = Curves.easeInOutCubic;

  // Motion distances. Fixed dp, never a share of the screen: a page that
  // travels a tenth of its width moves 36 dp on a phone and 80 dp on a tablet,
  // which is the same gesture reading as two different distances.

  /// How far a page travels as it arrives over the one it covers.
  static const double motionPageTravel = 32.0;

  /// How far the page underneath steps back while it is being covered. Half
  /// the arriving page's travel, so the pair reads as one depth change and the
  /// page below never looks like it is leaving.
  static const double motionPageRecede = 16.0;

  /// The last stretch overlay chrome travels into place. Chrome that appears
  /// where the finger already is has no room for a long entrance.
  static const double motionChromeTravel = 8.0;

  /// What a grid tile does when the reader picks it: it settles back inside
  /// its own slot, so the tile reads as an object taken hold of rather than a
  /// picture with a badge stuck on it. Transform only — the grid never
  /// re-lays out around a selection.
  static const double motionPickScale = 0.92;
}
