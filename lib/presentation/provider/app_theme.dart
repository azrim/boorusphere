import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/theme/app_actions.dart';
import 'package:boorusphere/presentation/theme/app_media_chrome.dart';
import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/color_palettes.dart';
import 'package:boorusphere/presentation/theme/contrast.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

class AppThemeData {
  const AppThemeData({
    required this.day,
    required this.night,
    required this.midnight,
  });

  factory AppThemeData.from({
    ColorScheme? light,
    ColorScheme? dark,
    ColorPalette colorPalette = ColorPalette.system,
  }) {
    final lightPreset = paletteColorsFor(colorPalette, Brightness.light);
    final darkPreset = paletteColorsFor(colorPalette, Brightness.dark);
    final accent = colorPalette.accentColor;
    // A curated palette owns the whole scheme, surfaces included. Only the
    // wallpaper palette and the single-seed palette leave the ramp to
    // Material: on Android 12+ the platform always hands back a dynamic
    // scheme, so preferring it would leave the presets with no effect.
    final lightScheme =
        lightPreset?.toScheme(Brightness.light) ??
        (accent == null
            ? light
            : ColorScheme.fromSeed(
                seedColor: accent,
                brightness: Brightness.light,
              ));
    final darkScheme =
        darkPreset?.toScheme(Brightness.dark) ??
        (accent == null
            ? dark
            : ColorScheme.fromSeed(
                seedColor: accent,
                brightness: Brightness.dark,
              ));
    // Harmonizing blends the scheme toward the wallpaper palette, which is
    // right for dynamic color and wrong for a palette the user picked by name.
    final harmonize = accent == null;

    return AppThemeData(
      day: _createThemeData(
        lightScheme,
        Brightness.light,
        harmonize: harmonize,
        // A theme that only ships a dark variant has no day ramp of its own,
        // so its day scheme is the generated one and keeps the tonal steps.
        preset: lightPreset != null,
      ),
      night: _createThemeData(
        darkScheme,
        Brightness.dark,
        harmonize: harmonize,
        preset: darkPreset != null,
      ),
      midnight: _createThemeDataMidnight(
        darkScheme,
        harmonize: harmonize,
        preset: darkPreset != null,
      ),
    );
  }

  final ThemeData day;
  final ThemeData night;
  final ThemeData midnight;

  static const defaultAccent = Color.fromARGB(255, 149, 30, 229);

  static final defLightScheme = ColorScheme.fromSeed(
    seedColor: defaultAccent,
    brightness: Brightness.light,
  );

  static final defDarkScheme = ColorScheme.fromSeed(
    seedColor: defaultAccent,
    brightness: Brightness.dark,
  );
}

/// Darkens [color] toward black by [percent], the shade the surface takes to
/// separate itself from the page background.
Color _shade(Color color, double percent) =>
    Color.lerp(color, const Color(0xFF000000), percent / 100)!;

ThemeData _createThemeData(
  ColorScheme? scheme,
  Brightness brightness, {
  bool harmonize = true,
  bool preset = false,
}) {
  final isDark = brightness == Brightness.dark;
  final defScheme = isDark
      ? AppThemeData.defDarkScheme
      : AppThemeData.defLightScheme;
  final base = scheme ?? defScheme;
  final harmonized = harmonize ? base.harmonized() : base;
  // A curated palette already decided its own page, panel and hairline;
  // shading or fading them would move the theme away from the colours it was
  // picked for. Generated schemes keep the tonal steps this app was built on.
  final surface = preset
      ? harmonized.surface
      : _shade(harmonized.surface, isDark ? 30 : 3);
  final colorScheme = preset
      ? harmonized
      : harmonized.copyWith(
          surface: surface,
          // The hairline is the only delimiter a section block has on the
          // page, so it is lifted until it reads as a line instead of
          // dissolving into the surface it outlines.
          outlineVariant: readableOnSurfaces(
            harmonized.outlineVariant,
            [
              surface,
              harmonized.surfaceContainerHigh,
              harmonized.surfaceContainerHighest,
            ],
            floor: 1.5,
            step: 0.08,
          ),
        );
  final origin = isDark ? ThemeData.dark() : ThemeData.light();
  final textTheme = AppTypography.textTheme(
    origin.textTheme,
    colorScheme.onSurface,
  );
  final roles = AppTextRoles.from(textTheme: textTheme, scheme: colorScheme);
  final actions = AppActionRoles.from(colorScheme);
  // Depth is a ladder, not a mood: the page is flat, a block sits one step
  // above it, chrome that floats over the content casts a shadow, and an
  // overlay that owns the screen casts a longer one. Everything reads
  // [DesignTokens.elevation*] so the ladder has four rungs and no more.
  final shadowColor = DesignTokens.shadowColor(colorScheme);
  return origin.copyWith(
    colorScheme: colorScheme,
    textTheme: textTheme,
    extensions: [
      roles,
      const AppSurfacePolicy(flat: false),
      AppMediaChrome.from(colorScheme),
      actions,
    ],
    shadowColor: shadowColor,
    // A bare icon used to fall back to the framework's pure white/black, which
    // ignores the palette's own text tone on the light themes.
    iconTheme: IconThemeData(color: colorScheme.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      scrolledUnderElevation: DesignTokens.elevationRaised,
      shadowColor: shadowColor,
    ),
    canvasColor: colorScheme.surface,
    scaffoldBackgroundColor: colorScheme.surface,
    cardTheme: origin.cardTheme.copyWith(
      color: colorScheme.surfaceContainerHigh,
      elevation: DesignTokens.elevationRaised,
      shadowColor: shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
    ),
    // Buttons stay flat: the fill carries the affordance, not a shadow. Their
    // labels are accents used as text, often on a dialog or a sheet, so they
    // read the raised-surface role instead of the page-only primary.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(elevation: 0),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: actions.primary),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: actions.primary),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      elevation: DesignTokens.elevationModal,
      shadowColor: shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
    ),
    // Menus, sheets and toasts separate by tone and shadow in day and night;
    // an outline box around them was a second edge for the same job. Midnight
    // puts the hairline back below, where black on black needs it.
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainer,
      elevation: DesignTokens.elevationOverlay,
      shadowColor: shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      modalBackgroundColor: colorScheme.surfaceContainer,
      elevation: DesignTokens.elevationOverlay,
      modalElevation: DesignTokens.elevationOverlay,
      shadowColor: shadowColor,
      dragHandleColor: colorScheme.onSurfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusXl),
        ),
      ),
    ),
    // The drawer sits on the page tone: a block inside it needs a step to
    // lift from, and `surfaceContainerLow` was too close to the block's own
    // tone for the step to read.
    drawerTheme: origin.drawerTheme.copyWith(
      backgroundColor: colorScheme.surface,
    ),
    // A toast is a card floating over the page, not a strip docked to the
    // bottom edge: it takes the raised block tone and floating elevation, and
    // only the action keeps the scheme's accent.
    snackBarTheme: origin.snackBarTheme.copyWith(
      behavior: SnackBarBehavior.floating,
      elevation: DesignTokens.elevationFloating,
      backgroundColor: colorScheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(color: colorScheme.onSurface),
      actionTextColor: actions.primary,
      insetPadding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        0,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
    ),
    // One type scale for every row: a 16 sp title over a 12 sp muted
    // description, so settings, server lists and drawers read the same.
    listTileTheme: origin.listTileTheme.copyWith(
      minVerticalPadding: DesignTokens.spacingCardInset,
      iconColor: colorScheme.onSurfaceVariant,
      titleTextStyle: roles.rowTitle,
      subtitleTextStyle: roles.rowSupporting,
    ),
  );
}

ThemeData _createThemeDataMidnight(
  ColorScheme? scheme, {
  bool harmonize = true,
  bool preset = false,
}) {
  final origin = _createThemeData(
    scheme,
    Brightness.dark,
    harmonize: harmonize,
    preset: preset,
  );
  final shadowColor = DesignTokens.shadowColor(origin.colorScheme);
  // The midnight rule is pure black surfaces. The container roles keep
  // their tonal lift so depth still reads, but anything painting plain
  // surface has to land on black instead of the night tint.
  final colorScheme = origin.colorScheme.copyWith(
    brightness: Brightness.dark,
    surface: Colors.black,
  );
  return origin.copyWith(
    // Midnight stays flat: the page is black on purpose, so a block keeps the
    // page tone and a hairline separates it, and overlays drop their shadow
    // because a shadow on black draws nothing.
    extensions: [
      ...origin.extensions.values,
      const AppSurfacePolicy(flat: true),
      // The backdrop here is the black of the page itself, so the scrim the
      // viewer paints is the black of the stage rather than the night tint.
      AppMediaChrome.from(colorScheme),
    ],
    // Every day/night overlay dropped its outline in favour of tone and
    // shadow; on black there is neither, so midnight keeps the hairline.
    popupMenuTheme: origin.popupMenuTheme.copyWith(
      color: Colors.black,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    dialogTheme: origin.dialogTheme.copyWith(
      backgroundColor: Colors.black,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    bottomSheetTheme: origin.bottomSheetTheme.copyWith(
      backgroundColor: Colors.black,
      modalBackgroundColor: Colors.black,
      elevation: 0,
      modalElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusXl),
        ),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    cardTheme: origin.cardTheme.copyWith(
      color: Colors.black,
      elevation: 0,
      shadowColor: shadowColor,
    ),
    snackBarTheme: origin.snackBarTheme.copyWith(
      backgroundColor: Colors.black,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    // The midnight rule is pure black with no tinting, so the app bar must not
    // pick up the surface tint when content scrolls under it.
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.black,
      foregroundColor: origin.colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    primaryColor: Colors.black,
    canvasColor: Colors.black,
    scaffoldBackgroundColor: Colors.black,
    drawerTheme: origin.drawerTheme.copyWith(backgroundColor: Colors.black),
    colorScheme: colorScheme,
  );
}
