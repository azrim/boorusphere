import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
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
    final accent = colorPalette.accentColor;
    // An explicit palette owns the scheme. Only the system palette follows the
    // wallpaper: on Android 12+ the platform always hands back a dynamic
    // scheme, so preferring it would leave the presets with no effect.
    final lightScheme = accent == null
        ? light
        : ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light);
    final darkScheme = accent == null
        ? dark
        : ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark);
    // Harmonizing blends the scheme toward the wallpaper palette, which is
    // right for dynamic color and wrong for a palette the user picked by name.
    final harmonize = accent == null;

    return AppThemeData(
      day: _createThemeData(
        lightScheme,
        Brightness.light,
        harmonize: harmonize,
      ),
      night: _createThemeData(
        darkScheme,
        Brightness.dark,
        harmonize: harmonize,
      ),
      midnight: _createThemeDataMidnight(darkScheme, harmonize: harmonize),
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
}) {
  final isDark = brightness == Brightness.dark;
  final defScheme = isDark
      ? AppThemeData.defDarkScheme
      : AppThemeData.defLightScheme;
  final base = scheme ?? defScheme;
  final harmonized = harmonize ? base.harmonized() : base;
  final colorScheme = harmonized.copyWith(
    surface: _shade(harmonized.surface, isDark ? 30 : 3),
    // The hairline is the only delimiter a section block has on the page, so
    // it has to stay visible instead of dissolving into the surface.
    outlineVariant: harmonized.outlineVariant.withValues(alpha: 0.45),
  );
  final origin = isDark ? ThemeData.dark() : ThemeData.light();
  return origin.copyWith(
    colorScheme: colorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
    ),
    canvasColor: colorScheme.surface,
    scaffoldBackgroundColor: colorScheme.surface,
    dialogTheme: DialogThemeData(backgroundColor: colorScheme.surface),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surface,
      modalBackgroundColor: colorScheme.surface,
      elevation: 0,
      modalElevation: 0,
      dragHandleColor: colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusXl),
        ),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    drawerTheme: origin.drawerTheme.copyWith(
      backgroundColor: colorScheme.surfaceContainerLow,
    ),
    snackBarTheme: origin.snackBarTheme.copyWith(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(DesignTokens.radiusLg),
          topRight: Radius.circular(DesignTokens.radiusLg),
        ),
      ),
      backgroundColor: colorScheme.primaryContainer,
      contentTextStyle: TextStyle(color: colorScheme.onPrimaryContainer),
    ),
    // One type scale for every row: a 16 sp title over a 12 sp muted
    // description, so settings, server lists and drawers read the same.
    listTileTheme: origin.listTileTheme.copyWith(
      minVerticalPadding: DesignTokens.spacingCardInset,
      iconColor: colorScheme.onSurfaceVariant,
      titleTextStyle: origin.textTheme.bodyLarge?.copyWith(
        color: colorScheme.onSurface,
      ),
      subtitleTextStyle: origin.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    ),
  );
}

ThemeData _createThemeDataMidnight(
  ColorScheme? scheme, {
  bool harmonize = true,
}) {
  final origin = _createThemeData(
    scheme,
    Brightness.dark,
    harmonize: harmonize,
  );
  return origin.copyWith(
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
    colorScheme: origin.colorScheme.copyWith(
      brightness: Brightness.dark,
      // The midnight rule is pure black surfaces. The container roles keep
      // their tonal lift so depth still reads, but anything painting plain
      // surface has to land on black instead of the night tint.
      surface: Colors.black,
    ),
  );
}
