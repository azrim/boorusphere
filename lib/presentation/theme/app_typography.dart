import 'package:flutter/material.dart';

/// The app's type scale.
///
/// One family, four weights, and a scale that only uses steps the system
/// already spends elsewhere: 11, 12, 14, 16, 20, 24 for chrome, and the
/// display steps for the few places that shout (a page title, an empty state).
///
/// Tracking does the work a second typeface would otherwise do: display sizes
/// tighten so a headline reads as one word, micro labels open up so 11 sp stays
/// legible on a phone held at arm's length. Nothing here is italic, and no
/// weight goes above bold.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Geist';

  /// The display face, used by the wordmark alone.
  static const String displayFamily = 'Poppins';

  /// Scripts Geist does not cover. Thai has no regional glyph variants, so a
  /// bundled face is safe; CJK is left to the platform, whose fallback is
  /// locale aware and would otherwise render Chinese in Japanese forms.
  static const List<String> fontFallback = ['Noto Sans Thai'];

  /// Weights the bundle ships. A request for anything else snaps to the
  /// nearest of these instead of synthesising a fake bold.
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  static TextTheme textTheme(TextTheme base, Color color) {
    TextStyle style(
      double size,
      double height,
      FontWeight weight,
      double tracking,
    ) => _style(size, height, weight, tracking, color);

    return base.copyWith(
      displayLarge: style(57, 1.12, bold, -1.5),
      displayMedium: style(45, 1.16, bold, -1.2),
      displaySmall: style(36, 1.22, semiBold, -1.0),
      headlineLarge: style(32, 1.25, semiBold, -0.8),
      headlineMedium: style(28, 1.29, semiBold, -0.6),
      headlineSmall: style(24, 1.33, semiBold, -0.4),
      titleLarge: style(20, 1.4, semiBold, -0.2),
      titleMedium: style(16, 1.5, semiBold, -0.1),
      titleSmall: style(14, 1.43, semiBold, 0),
      bodyLarge: style(16, 1.5, regular, 0),
      bodyMedium: style(14, 1.5, regular, 0.1),
      bodySmall: style(12, 1.4, regular, 0.2),
      labelLarge: style(14, 1.43, semiBold, 0),
      labelMedium: style(12, 1.33, medium, 0.3),
      labelSmall: style(11, 1.45, medium, 0.2),
    );
  }

  static TextStyle _style(
    double size,
    double height,
    FontWeight weight,
    double tracking,
    Color color,
  ) {
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color,
    );
  }
}

/// The four roles every chrome surface shares: a section label, a field label,
/// a row title, and the muted line under it.
///
/// They live on the theme so a screen cannot invent a fifth. A settings row, a
/// sheet row and a drawer row then read the same size and weight even though
/// they are built by different widgets.
@immutable
class AppTextRoles extends ThemeExtension<AppTextRoles> {
  const AppTextRoles({
    required this.sectionLabel,
    required this.fieldLabel,
    required this.rowTitle,
    required this.rowSupporting,
    required this.numeric,
  });

  /// Derives the four roles from a text theme and a scheme.
  factory AppTextRoles.from({
    required TextTheme textTheme,
    required ColorScheme scheme,
  }) {
    return AppTextRoles(
      sectionLabel: textTheme.labelSmall!.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: AppTypography.bold,
        letterSpacing: 1.4,
      ),
      fieldLabel: textTheme.labelSmall!.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      rowTitle: textTheme.bodyLarge!.copyWith(color: scheme.onSurface),
      rowSupporting: textTheme.bodySmall!.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      numeric: textTheme.bodyMedium!.copyWith(
        color: scheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// 11 sp, bold, opened tracking: the small caps line that names a section.
  /// Callers uppercase the text; the role stays case-agnostic.
  final TextStyle sectionLabel;

  /// 11 sp muted, sentence case: the label above a field.
  final TextStyle fieldLabel;

  /// 16 sp on-surface: the only primary text in a row.
  final TextStyle rowTitle;

  /// 12 sp muted: the line that explains a row title.
  final TextStyle rowSupporting;

  /// Body size with tabular figures, so counts, scores and dimensions line up
  /// down a column instead of drifting with each digit.
  final TextStyle numeric;

  /// The roles of the active theme.
  ///
  /// A theme without the extension — a test harness, a preview — gets the
  /// roles derived from its own text theme instead of an assertion, so a
  /// widget built outside the app still reads the shared scale.
  static AppTextRoles of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppTextRoles>() ??
        AppTextRoles.from(
          textTheme: theme.textTheme,
          scheme: theme.colorScheme,
        );
  }

  @override
  AppTextRoles copyWith({
    TextStyle? sectionLabel,
    TextStyle? fieldLabel,
    TextStyle? rowTitle,
    TextStyle? rowSupporting,
    TextStyle? numeric,
  }) {
    return AppTextRoles(
      sectionLabel: sectionLabel ?? this.sectionLabel,
      fieldLabel: fieldLabel ?? this.fieldLabel,
      rowTitle: rowTitle ?? this.rowTitle,
      rowSupporting: rowSupporting ?? this.rowSupporting,
      numeric: numeric ?? this.numeric,
    );
  }

  @override
  AppTextRoles lerp(ThemeExtension<AppTextRoles>? other, double t) {
    if (other is! AppTextRoles) return this;
    return AppTextRoles(
      sectionLabel: TextStyle.lerp(sectionLabel, other.sectionLabel, t)!,
      fieldLabel: TextStyle.lerp(fieldLabel, other.fieldLabel, t)!,
      rowTitle: TextStyle.lerp(rowTitle, other.rowTitle, t)!,
      rowSupporting: TextStyle.lerp(rowSupporting, other.rowSupporting, t)!,
      numeric: TextStyle.lerp(numeric, other.numeric, t)!,
    );
  }
}
