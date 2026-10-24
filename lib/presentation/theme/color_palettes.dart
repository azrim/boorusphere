import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:flutter/material.dart';

/// The colours a preset palette owns, for one brightness.
///
/// Only the roles a theme actually decides are stored. The container, inverse
/// and state roles are derived in [toScheme], so every palette keeps the same
/// structure while its page, cards, text and accents come from the theme
/// itself instead of from a generated tonal ramp.
@immutable
class PaletteColors {
  const PaletteColors({
    required this.background,
    required this.panel,
    required this.text,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.border,
    required this.error,
  });

  /// The page surface every screen paints behind its content.
  final Color background;

  /// Cards, sheets, inputs and menus: the surface that sits on [background].
  final Color panel;

  final Color text;

  /// Secondary text and icons; kept above 4.5:1 on both surfaces.
  final Color muted;

  final Color primary;
  final Color secondary;
  final Color tertiary;

  /// Hairlines and section dividers.
  final Color border;

  final Color error;

  /// Builds the full Material scheme from the palette's own colours.
  ColorScheme toScheme(Brightness brightness) {
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: _readableOn(primary),
      primaryContainer: _tint(primary, background),
      onPrimaryContainer: text,
      secondary: secondary,
      onSecondary: _readableOn(secondary),
      secondaryContainer: _tint(secondary, background),
      onSecondaryContainer: text,
      tertiary: tertiary,
      onTertiary: _readableOn(tertiary),
      tertiaryContainer: _tint(tertiary, background),
      onTertiaryContainer: text,
      error: error,
      onError: _readableOn(error),
      errorContainer: _tint(error, background),
      onErrorContainer: text,
      surface: background,
      onSurface: text,
      onSurfaceVariant: muted,
      surfaceDim: _mix(background, panel, 0.5),
      surfaceBright: _mix(panel, text, 0.08),
      surfaceContainerLowest: background,
      surfaceContainerLow: _mix(background, panel, 0.45),
      surfaceContainer: _mix(background, panel, 0.75),
      surfaceContainerHigh: panel,
      surfaceContainerHighest: _mix(panel, text, 0.05),
      outline: border,
      outlineVariant: border,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: text,
      onInverseSurface: background,
      inversePrimary: primary,
    );
  }
}

/// The curated colours for [palette] at [brightness], or null when the scheme
/// is generated instead of curated (the wallpaper palette, or a single seed).
PaletteColors? paletteColorsFor(ColorPalette palette, Brightness brightness) {
  final pair = _palettes[palette];
  if (pair == null) return null;
  return brightness == Brightness.dark ? pair.$1 : pair.$2;
}

/// Black or white, whichever stays readable on [color].
Color _readableOn(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

/// A low-emphasis fill of [accent] over [base], used for the container roles.
Color _tint(Color accent, Color base) {
  return Color.alphaBlend(accent.withValues(alpha: 0.20), base);
}

Color _mix(Color from, Color to, double amount) {
  return Color.lerp(from, to, amount)!;
}

const _palettes = <ColorPalette, (PaletteColors, PaletteColors)>{
  ColorPalette.dracula: (
    PaletteColors(
      background: Color(0xFF282A36),
      panel: Color(0xFF343746),
      text: Color(0xFFF8F8F2),
      muted: Color(0xFF9AA2C4),
      primary: Color(0xFFBD93F9),
      secondary: Color(0xFFFF79C6),
      tertiary: Color(0xFF8BE9FD),
      border: Color(0xFF44475A),
      error: Color(0xFFFF5555),
    ),
    PaletteColors(
      background: Color(0xFFFFFBEB),
      panel: Color(0xFFF2EBDC),
      text: Color(0xFF1F1F1F),
      muted: Color(0xFF5F5A45),
      primary: Color(0xFF644AC9),
      secondary: Color(0xFFA3144D),
      tertiary: Color(0xFF036A96),
      border: Color(0xFFCFCFDE),
      error: Color(0xFFCB3A2A),
    ),
  ),
  ColorPalette.catpuccin: (
    PaletteColors(
      background: Color(0xFF1E1E2E),
      panel: Color(0xFF313244),
      text: Color(0xFFCDD6F4),
      muted: Color(0xFFA6ADC8),
      primary: Color(0xFFCBA6F7),
      secondary: Color(0xFFF5C2E7),
      tertiary: Color(0xFF89B4FA),
      border: Color(0xFF45475A),
      error: Color(0xFFF38BA8),
    ),
    PaletteColors(
      background: Color(0xFFEFF1F5),
      panel: Color(0xFFE6E9EF),
      text: Color(0xFF4C4F69),
      muted: Color(0xFF5A5D75),
      primary: Color(0xFF8839EF),
      secondary: Color(0xFFC2187A),
      tertiary: Color(0xFF1E66F5),
      border: Color(0xFFCCD0DA),
      error: Color(0xFFD20F39),
    ),
  ),
  ColorPalette.nord: (
    PaletteColors(
      background: Color(0xFF2E3440),
      panel: Color(0xFF3B4252),
      text: Color(0xFFECEFF4),
      muted: Color(0xFFA7B1C2),
      primary: Color(0xFF88C0D0),
      secondary: Color(0xFFB48EAD),
      tertiary: Color(0xFF8FBCBB),
      border: Color(0xFF4C566A),
      error: Color(0xFFD98A92),
    ),
    PaletteColors(
      background: Color(0xFFECEFF4),
      panel: Color(0xFFE5E9F0),
      text: Color(0xFF2E3440),
      muted: Color(0xFF4C566A),
      primary: Color(0xFF4F7099),
      secondary: Color(0xFF8F5F87),
      tertiary: Color(0xFF7E5C7E),
      border: Color(0xFFD8DEE9),
      error: Color(0xFFA9454E),
    ),
  ),
  ColorPalette.solarized: (
    PaletteColors(
      background: Color(0xFF002B36),
      panel: Color(0xFF073642),
      text: Color(0xFFEEE8D5),
      muted: Color(0xFF93A1A1),
      primary: Color(0xFF268BD2),
      secondary: Color(0xFF2AA198),
      tertiary: Color(0xFFB58900),
      border: Color(0xFF0F4B57),
      error: Color(0xFFF07167),
    ),
    PaletteColors(
      background: Color(0xFFFDF6E3),
      panel: Color(0xFFEEE8D5),
      text: Color(0xFF073642),
      muted: Color(0xFF526569),
      primary: Color(0xFF1F73AE),
      secondary: Color(0xFF17786F),
      tertiary: Color(0xFF8F6B00),
      border: Color(0xFFDDD6C1),
      error: Color(0xFFC02B28),
    ),
  ),
  ColorPalette.gruvbox: (
    PaletteColors(
      background: Color(0xFF282828),
      panel: Color(0xFF3C3836),
      text: Color(0xFFEBDBB2),
      muted: Color(0xFFB5A78F),
      primary: Color(0xFFFABD2F),
      secondary: Color(0xFF83A598),
      tertiary: Color(0xFFD3869B),
      border: Color(0xFF504945),
      error: Color(0xFFFB4934),
    ),
    PaletteColors(
      background: Color(0xFFFBF1C7),
      panel: Color(0xFFEBDBB2),
      text: Color(0xFF3C3836),
      muted: Color(0xFF665C54),
      primary: Color(0xFF96600F),
      secondary: Color(0xFF076678),
      tertiary: Color(0xFF8F3F71),
      border: Color(0xFFD5C4A1),
      error: Color(0xFF9D0006),
    ),
  ),
  ColorPalette.oneDark: (
    PaletteColors(
      background: Color(0xFF282C34),
      panel: Color(0xFF333842),
      text: Color(0xFFABB2BF),
      muted: Color(0xFF9AA1AD),
      primary: Color(0xFF61AFEF),
      secondary: Color(0xFFC678DD),
      tertiary: Color(0xFF56B6C2),
      border: Color(0xFF3E4451),
      error: Color(0xFFE06C75),
    ),
    PaletteColors(
      background: Color(0xFFFAFAFA),
      panel: Color(0xFFF0F0F0),
      text: Color(0xFF383A42),
      muted: Color(0xFF696C77),
      primary: Color(0xFF2F63D6),
      secondary: Color(0xFFA626A4),
      tertiary: Color(0xFF0184BC),
      border: Color(0xFFE5E5E6),
      error: Color(0xFFE45649),
    ),
  ),
  ColorPalette.monokai: (
    PaletteColors(
      background: Color(0xFF272822),
      panel: Color(0xFF3E3D32),
      text: Color(0xFFF8F8F2),
      muted: Color(0xFFA9A99A),
      primary: Color(0xFFA6E22E),
      secondary: Color(0xFFFD971F),
      tertiary: Color(0xFF66D9EF),
      border: Color(0xFF49483E),
      error: Color(0xFFFF6188),
    ),
    PaletteColors(
      background: Color(0xFFF9F8F5),
      panel: Color(0xFFF0EFEA),
      text: Color(0xFF272822),
      muted: Color(0xFF5B5A52),
      primary: Color(0xFF5A7A00),
      secondary: Color(0xFFA85200),
      tertiary: Color(0xFF00738C),
      border: Color(0xFFE2E0D8),
      error: Color(0xFFC7254E),
    ),
  ),
  ColorPalette.github: (
    PaletteColors(
      background: Color(0xFF0D1117),
      panel: Color(0xFF161B22),
      text: Color(0xFFC9D1D9),
      muted: Color(0xFF8B949E),
      primary: Color(0xFF58A6FF),
      secondary: Color(0xFFBC8CFF),
      tertiary: Color(0xFF3FB950),
      border: Color(0xFF30363D),
      error: Color(0xFFF85149),
    ),
    PaletteColors(
      background: Color(0xFFFFFFFF),
      panel: Color(0xFFF6F8FA),
      text: Color(0xFF24292F),
      muted: Color(0xFF57606A),
      primary: Color(0xFF0969DA),
      secondary: Color(0xFF8250DF),
      tertiary: Color(0xFF1A7F37),
      border: Color(0xFFD0D7DE),
      error: Color(0xFFCF222E),
    ),
  ),
};
