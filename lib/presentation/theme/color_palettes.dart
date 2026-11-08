import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/theme/contrast.dart';
import 'package:flutter/material.dart';

/// The colours a preset palette owns, for one brightness.
///
/// An editor theme ships a surface ramp of its own: a page, the panels that
/// float on it, and the tone a selected row takes, so the ramp is stored as
/// the theme designed it. [toScheme] maps those tones onto Material roles and
/// never invents a surface by mixing two others.
///
/// Accents keep the theme's hue; only their lightness moves, and only as far
/// as the 4.5:1 floor requires, because an editor paints syntax on a page and
/// a light theme's pink or yellow is often too pale to carry a control. Text,
/// muted text and the labels on container tints are lifted against every tone
/// they can land on, and the hairline is lifted until it reads as a line
/// instead of dissolving into the block it outlines.
@immutable
class PaletteColors {
  const PaletteColors({
    required this.background,
    required this.containerLow,
    required this.container,
    required this.containerHigh,
    required this.containerHighest,
    required this.border,
    required this.line,
    required this.text,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.error,
  });

  /// The page surface every screen paints behind its content.
  final Color background;

  /// One step off the page, towards the panel.
  final Color containerLow;

  /// Cards, sheets, inputs and menus: the surface that sits on [background].
  final Color container;

  /// One step above the panel.
  final Color containerHigh;

  /// The tone a selected or hovered row takes in the theme it came from.
  final Color containerHighest;

  /// The soft hairline: a tone one step off the surface it sits on.
  final Color border;

  /// The strong line: the theme's own emphasis rule.
  final Color line;

  /// The theme's foreground, as written. A theme is often tuned for one
  /// surface, so [toScheme] lifts it to 4.5:1 on every tone it can land on.
  final Color text;

  /// Secondary text and icons, as the theme writes them. A comment tone is
  /// often below 4.5:1 on the page, so [toScheme] lifts it to the floor.
  final Color muted;

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color error;

  /// Builds the full Material scheme from the palette's own colours.
  ColorScheme toScheme(Brightness brightness) {
    final accent = readableOnSurfaces(primary, [background]);
    final accentSecondary = readableOnSurfaces(secondary, [background]);
    final accentTertiary = readableOnSurfaces(tertiary, [background]);
    final accentError = readableOnSurfaces(error, [background]);
    final primaryContainer = _tint(accent, background);
    final secondaryContainer = _tint(accentSecondary, background);
    final tertiaryContainer = _tint(accentTertiary, background);
    final errorContainer = _tint(accentError, background);
    // A foreground is painted on four tones, not one: the page, the panel, a
    // block and the selection fill. Lifting against all of them is what keeps
    // a supporting line readable inside a section and on a chip; a page-only
    // floor left the raised tones under 4.5:1.
    final surfaces = [
      background,
      containerLow,
      container,
      containerHigh,
      containerHighest,
    ];

    return ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: readableOn(accent),
      primaryContainer: primaryContainer,
      // The tint moves the base colour, so its label is derived from the tint
      // rather than reusing the page's text tone.
      onPrimaryContainer: readableOnSurfaces(text, [primaryContainer]),
      secondary: accentSecondary,
      onSecondary: readableOn(accentSecondary),
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: readableOnSurfaces(text, [secondaryContainer]),
      tertiary: accentTertiary,
      onTertiary: readableOn(accentTertiary),
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: readableOnSurfaces(text, [tertiaryContainer]),
      error: accentError,
      onError: readableOn(accentError),
      errorContainer: errorContainer,
      onErrorContainer: readableOnSurfaces(text, [errorContainer]),
      surface: background,
      onSurface: readableOnSurfaces(text, surfaces),
      onSurfaceVariant: readableOnSurfaces(muted, surfaces),
      // Both of these stay inside the theme's own ramp.
      surfaceDim: containerLow,
      // Bright is the page's own end of the ramp: the lightest tone in a light
      // theme, the raised end in a dark one. Mapping it to the block tone put
      // it on the wrong side in every light palette.
      surfaceBright: brightness == Brightness.dark ? containerHigh : background,
      surfaceContainerLowest: background,
      surfaceContainerLow: containerLow,
      surfaceContainer: container,
      surfaceContainerHigh: containerHigh,
      surfaceContainerHighest: containerHighest,
      outline: line,
      outlineVariant: _hairline(border, line, surfaces),
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: text,
      onInverseSurface: background,
      inversePrimary: accent,
    );
  }
}

/// The curated colours for [palette] at [brightness], or null when the scheme
/// is generated instead of curated (the wallpaper palette, a single seed, or
/// the day side of a theme that only ships a dark variant).
PaletteColors? paletteColorsFor(ColorPalette palette, Brightness brightness) {
  final pair = _palettes[palette];
  if (pair == null) return null;
  return brightness == Brightness.dark ? pair.$1 : pair.$2;
}

/// A low-emphasis fill of [accent] over [base], used for the container roles.
Color _tint(Color accent, Color base) {
  return Color.alphaBlend(accent.withValues(alpha: 0.20), base);
}

/// The soft hairline, lifted off every tone it can outline.
///
/// A border that equals the block's own fill draws nothing, and in Midnight
/// the hairline is the only boundary a block has. It is also kept a different
/// tone from the emphasis rule so the two line grades never collapse.
Color _hairline(Color border, Color line, List<Color> surfaces) {
  final hairline = readableOnSurfaces(border, surfaces, floor: 1.5, step: 0.08);
  if (hairline.toARGB32() != line.toARGB32()) return hairline;

  return readableOnSurfaces(
    Color.lerp(hairline, readableOn(surfaces.last), 0.15)!,
    surfaces,
    floor: 1.5,
    step: 0.08,
  );
}

const _palettes = <ColorPalette, (PaletteColors, PaletteColors?)>{
  // Dracula Classic and Alucard, from the published ramp: page, background
  // dark, floating/background light, background lighter, selection, current
  // line.
  ColorPalette.dracula: (
    PaletteColors(
      background: Color(0xFF282A36),
      containerLow: Color(0xFF21222C),
      container: Color(0xFF343746),
      containerHigh: Color(0xFF424450),
      containerHighest: Color(0xFF44475A),
      border: Color(0xFF44475A),
      line: Color(0xFF6272A4),
      text: Color(0xFFF8F8F2),
      muted: Color(0xFF6272A4),
      primary: Color(0xFFBD93F9),
      secondary: Color(0xFFFF79C6),
      tertiary: Color(0xFF8BE9FD),
      error: Color(0xFFFF5555),
    ),
    PaletteColors(
      background: Color(0xFFFFFBEB),
      containerLow: Color(0xFFEFEDDC),
      container: Color(0xFFECE9DF),
      containerHigh: Color(0xFFDEDCCF),
      containerHighest: Color(0xFFCFCFDE),
      border: Color(0xFFCFCFDE),
      line: Color(0xFF6C664B),
      text: Color(0xFF1F1F1F),
      muted: Color(0xFF5F5A45),
      primary: Color(0xFF644AC9),
      secondary: Color(0xFFA3144D),
      tertiary: Color(0xFF036A96),
      error: Color(0xFFCB3A2A),
    ),
  ),
  // Catppuccin Mocha and Latte: base, mantle, crust, surface0-2, overlay0.
  ColorPalette.catpuccin: (
    PaletteColors(
      background: Color(0xFF1E1E2E),
      containerLow: Color(0xFF181825),
      container: Color(0xFF313244),
      containerHigh: Color(0xFF45475A),
      containerHighest: Color(0xFF585B70),
      border: Color(0xFF45475A),
      line: Color(0xFF6C7086),
      text: Color(0xFFCDD6F4),
      muted: Color(0xFFA6ADC8),
      primary: Color(0xFFCBA6F7),
      secondary: Color(0xFFF5C2E7),
      tertiary: Color(0xFF89B4FA),
      error: Color(0xFFF38BA8),
    ),
    PaletteColors(
      background: Color(0xFFEFF1F5),
      containerLow: Color(0xFFE6E9EF),
      container: Color(0xFFDCE0E8),
      containerHigh: Color(0xFFCCD0DA),
      containerHighest: Color(0xFFBCC0CC),
      border: Color(0xFFCCD0DA),
      line: Color(0xFF9CA0B0),
      text: Color(0xFF4C4F69),
      muted: Color(0xFF5C5F77),
      primary: Color(0xFF8839EF),
      secondary: Color(0xFFEA76CB),
      tertiary: Color(0xFF1E66F5),
      error: Color(0xFFD20F39),
    ),
  ),
  // Nord ships one polarity: polar night nord0-3, with frost and aurora as
  // accents. There is no official light variant, so day falls back to a
  // generated light scheme seeded from the frost blue.
  ColorPalette.nord: (
    PaletteColors(
      background: Color(0xFF2E3440),
      containerLow: Color(0xFF3B4252),
      container: Color(0xFF3B4252),
      containerHigh: Color(0xFF434C5E),
      containerHighest: Color(0xFF4C566A),
      border: Color(0xFF434C5E),
      line: Color(0xFF4C566A),
      text: Color(0xFFECEFF4),
      muted: Color(0xFFA7B1C2),
      primary: Color(0xFF88C0D0),
      secondary: Color(0xFFB48EAD),
      tertiary: Color(0xFF8FBCBB),
      error: Color(0xFFBF616A),
    ),
    null,
  ),
  // Solarized defines base03 as the page, base02 as the raised surface and
  // base01 as the comment tone; the two chip steps are taken between them.
  // Its light variant is warm paper, so it stays dark only and day is
  // generated from the accent this palette is picked by.
  ColorPalette.solarized: (
    PaletteColors(
      background: Color(0xFF002B36),
      containerLow: Color(0xFF073642),
      container: Color(0xFF073642),
      containerHigh: Color(0xFF17414C),
      containerHighest: Color(0xFF21505A),
      border: Color(0xFF17414C),
      line: Color(0xFF586E75),
      text: Color(0xFFEEE8D5),
      muted: Color(0xFF93A1A1),
      primary: Color(0xFF268BD2),
      secondary: Color(0xFF2AA198),
      tertiary: Color(0xFFB58900),
      error: Color(0xFFDC322F),
    ),
    null,
  ),
  // Gruvbox bg0 through bg4. Its light variant is the warmest page of any
  // theme here, so it stays dark only.
  ColorPalette.gruvbox: (
    PaletteColors(
      background: Color(0xFF282828),
      containerLow: Color(0xFF1D2021),
      container: Color(0xFF3C3836),
      containerHigh: Color(0xFF504945),
      containerHighest: Color(0xFF665C54),
      border: Color(0xFF504945),
      line: Color(0xFF665C54),
      text: Color(0xFFEBDBB2),
      muted: Color(0xFFB5A78F),
      primary: Color(0xFFFABD2F),
      secondary: Color(0xFF83A598),
      tertiary: Color(0xFFD3869B),
      error: Color(0xFFFB4934),
    ),
    null,
  ),
  // One Dark and One Light workbench: editor, sidebar, widget, border.
  ColorPalette.oneDark: (
    PaletteColors(
      background: Color(0xFF282C34),
      containerLow: Color(0xFF21252B),
      container: Color(0xFF2C313A),
      containerHigh: Color(0xFF333842),
      containerHighest: Color(0xFF3E4451),
      border: Color(0xFF3E4451),
      line: Color(0xFF4B5263),
      text: Color(0xFFABB2BF),
      muted: Color(0xFF9AA1AD),
      primary: Color(0xFF61AFEF),
      secondary: Color(0xFFC678DD),
      tertiary: Color(0xFF56B6C2),
      error: Color(0xFFE06C75),
    ),
    PaletteColors(
      background: Color(0xFFFAFAFA),
      containerLow: Color(0xFFF0F0F1),
      container: Color(0xFFEAEAEB),
      containerHigh: Color(0xFFDBDBDC),
      containerHighest: Color(0xFFD0D0D1),
      border: Color(0xFFDBDBDC),
      line: Color(0xFFA0A1A7),
      text: Color(0xFF383A42),
      muted: Color(0xFF696C77),
      primary: Color(0xFF4078F2),
      secondary: Color(0xFFA626A4),
      tertiary: Color(0xFF0184BC),
      error: Color(0xFFE45649),
    ),
  ),
  // Monokai is dark only: background, current line, selection, comment. The
  // two chip steps are taken between the selection and the comment.
  ColorPalette.monokai: (
    PaletteColors(
      background: Color(0xFF272822),
      containerLow: Color(0xFF272822),
      container: Color(0xFF3E3D32),
      containerHigh: Color(0xFF49483E),
      containerHighest: Color(0xFF545346),
      border: Color(0xFF49483E),
      line: Color(0xFF75715E),
      text: Color(0xFFF8F8F2),
      muted: Color(0xFFA9A99A),
      primary: Color(0xFFA6E22E),
      secondary: Color(0xFFFD971F),
      tertiary: Color(0xFF66D9EF),
      error: Color(0xFFF92672),
    ),
    null,
  ),
  // GitHub Primer: canvas default, subtle, inset, and the border ramp.
  ColorPalette.github: (
    PaletteColors(
      background: Color(0xFF0D1117),
      containerLow: Color(0xFF010409),
      container: Color(0xFF161B22),
      containerHigh: Color(0xFF21262D),
      containerHighest: Color(0xFF30363D),
      border: Color(0xFF30363D),
      line: Color(0xFF484F58),
      text: Color(0xFFE6EDF3),
      muted: Color(0xFF7D8590),
      primary: Color(0xFF58A6FF),
      secondary: Color(0xFFBC8CFF),
      tertiary: Color(0xFF3FB950),
      error: Color(0xFFF85149),
    ),
    PaletteColors(
      background: Color(0xFFFFFFFF),
      containerLow: Color(0xFFF6F8FA),
      container: Color(0xFFF6F8FA),
      containerHigh: Color(0xFFEAEEF2),
      containerHighest: Color(0xFFD8DEE4),
      border: Color(0xFFD0D7DE),
      line: Color(0xFFAFB8C1),
      text: Color(0xFF1F2328),
      muted: Color(0xFF656D76),
      primary: Color(0xFF0969DA),
      secondary: Color(0xFF8250DF),
      tertiary: Color(0xFF1A7F37),
      error: Color(0xFFCF222E),
    ),
  ),
  // Tokyo Night: night is bg, bg_dark, bg_float, bg_highlight, border. Day is
  // the cool grey workbench, with the two chip steps taken between its
  // highlight and its comment tone.
  ColorPalette.tokyoNight: (
    PaletteColors(
      background: Color(0xFF1A1B26),
      containerLow: Color(0xFF16161E),
      container: Color(0xFF1F2335),
      containerHigh: Color(0xFF292E42),
      containerHighest: Color(0xFF414868),
      border: Color(0xFF292E42),
      line: Color(0xFF3B4261),
      text: Color(0xFFC0CAF5),
      muted: Color(0xFF565F89),
      primary: Color(0xFF7AA2F7),
      secondary: Color(0xFFBB9AF7),
      tertiary: Color(0xFF7DCFFF),
      error: Color(0xFFF7768E),
    ),
    PaletteColors(
      background: Color(0xFFE1E2E7),
      containerLow: Color(0xFFD0D5E3),
      container: Color(0xFFD0D5E3),
      containerHigh: Color(0xFFC4C8DA),
      containerHighest: Color(0xFFB4B9D1),
      border: Color(0xFFC4C8DA),
      line: Color(0xFFA4AAC7),
      text: Color(0xFF3760BF),
      muted: Color(0xFF848CB5),
      primary: Color(0xFF2E7DE9),
      secondary: Color(0xFF9854F1),
      tertiary: Color(0xFF007197),
      error: Color(0xFFF52A65),
    ),
  ),
  // Ayu publishes a background, a foreground and one dimmed tone per polarity,
  // so the chip steps are taken between those instead of being invented.
  ColorPalette.ayu: (
    PaletteColors(
      background: Color(0xFF0F1419),
      containerLow: Color(0xFF181E26),
      container: Color(0xFF212733),
      containerHigh: Color(0xFF2D3542),
      containerHighest: Color(0xFF384451),
      border: Color(0xFF2D3542),
      line: Color(0xFF3E4B59),
      text: Color(0xFFBFBDB6),
      muted: Color(0xFF626A73),
      primary: Color(0xFFE6B450),
      secondary: Color(0xFF59C2FF),
      tertiary: Color(0xFFD2A6FF),
      error: Color(0xFFF07178),
    ),
    PaletteColors(
      background: Color(0xFFFAFAFA),
      containerLow: Color(0xFFF3F4F5),
      container: Color(0xFFEDEEF0),
      containerHigh: Color(0xFFE4E6E8),
      containerHighest: Color(0xFFD8DBDE),
      border: Color(0xFFE4E6E8),
      line: Color(0xFFC7CCD1),
      text: Color(0xFF5C6773),
      muted: Color(0xFF828C99),
      primary: Color(0xFFFF6A00),
      secondary: Color(0xFF41A6D9),
      tertiary: Color(0xFFA37ACC),
      error: Color(0xFFF07178),
    ),
  ),
};
