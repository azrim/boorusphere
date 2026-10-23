import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:tinycolor2/tinycolor2.dart';

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
    final accent = colorPalette.accentColor ?? defaultAccent;

    final lightScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    );

    return AppThemeData(
      day: _createThemeData(light ?? lightScheme, Brightness.light),
      night: _createThemeData(dark ?? darkScheme, Brightness.dark),
      midnight: _createThemeDataMidnight(dark ?? darkScheme),
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

ThemeData _createThemeData(ColorScheme? scheme, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final defScheme = isDark
      ? AppThemeData.defDarkScheme
      : AppThemeData.defLightScheme;
  final harmonized = scheme?.harmonized() ?? defScheme;
  final colorScheme = harmonized.copyWith(
    surface: harmonized.surface.shade(isDark ? 30 : 3),
    outlineVariant: harmonized.outlineVariant.withValues(alpha: 0.3),
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
    listTileTheme: origin.listTileTheme.copyWith(
      minVerticalPadding: 12,
      iconColor: colorScheme.onSurfaceVariant,
    ),
  );
}

ThemeData _createThemeDataMidnight(ColorScheme? scheme) {
  final origin = _createThemeData(scheme, Brightness.dark);
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
