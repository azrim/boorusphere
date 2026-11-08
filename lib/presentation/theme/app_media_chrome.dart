import 'package:flutter/material.dart';

/// The one alpha a scrim takes over artwork: enough of the picture is still
/// visible through it, but a glyph on top of it never has to compete with the
/// brightest pixel the booru serves.
const double _kScrimAlpha = 0.54;

/// The middle stop of the timeline's overlay gradient, where the band has to
/// clear the artwork faster than a straight ramp would.
const double _kScrimMidAlpha = 0.18;

/// A wash behind a single control (the pause circle, the tap-to-pause tint),
/// lighter than a scrim because it covers the whole frame rather than an edge.
const double _kScrimSoftAlpha = 0.38;

/// The plate an on-image label sits on: stronger than a scrim, since the label
/// is small and has no gradient helping it.
const double _kPlateAlpha = 0.70;

/// The unfilled part of a progress track drawn over artwork.
const double _kTrackAlpha = 0.24;

/// A secondary mark next to a primary one, such as the swipe-mode glyph.
const double _kMutedAlpha = 0.70;

/// A control that cannot be used: the same value Material uses for disabled
/// foregrounds, so a greyed-out button reads the same here as it does on a page.
const double _kDisabledAlpha = 0.38;

/// The shadow weight behind a plain on-image label, and the stronger one for
/// coloured text, which carries less contrast than the light label and so needs
/// more edge behind it.
const double _kLabelShadowAlpha = 0.50;
const double _kLabelShadowStrongAlpha = 0.80;

/// The paint of everything drawn *on top of* artwork: the post viewer's chrome,
/// its gesture feedback, and the timeline's on-image overlays.
///
/// Artwork is arbitrary, so a scheme's own surface tone cannot be its backdrop
/// and the palette's `onSurface` cannot be its text color: a light palette
/// hands over a dark `onSurface`, which would vanish the moment it lands on a
/// dark scrim. This role set fixes that relationship once, in the theme, out of
/// the palette's neutral pair, so widgets read a role instead of reaching for
/// [Colors.white] and [Colors.black] at every call site. A curated palette or
/// the Midnight rule can override it there, in the one place hex is allowed.
@immutable
class AppMediaChrome extends ThemeExtension<AppMediaChrome> {
  const AppMediaChrome({
    required this.stage,
    required this.foreground,
    required this.foregroundMuted,
    required this.foregroundDisabled,
    required this.scrim,
    required this.scrimMid,
    required this.scrimSoft,
    required this.plate,
    required this.track,
    required this.labelShadow,
    required this.labelShadowStrong,
  });

  /// The neutral pair of [scheme], decided by luminance rather than brightness:
  /// whatever the palette calls its page is the lightest thing it owns when the
  /// page is light, and its `onSurface` is when the page is dark. Over artwork
  /// the backdrop is always the dark one and the glyph always the light one,
  /// whichever theme is active.
  factory AppMediaChrome.from(ColorScheme scheme) {
    final pageIsLight =
        scheme.surface.computeLuminance() > scheme.onSurface.computeLuminance();
    final light = pageIsLight ? scheme.surface : scheme.onSurface;
    final dark = pageIsLight ? scheme.onSurface : scheme.surface;

    return AppMediaChrome(
      stage: dark,
      foreground: light,
      foregroundMuted: light.withValues(alpha: _kMutedAlpha),
      foregroundDisabled: light.withValues(alpha: _kDisabledAlpha),
      scrim: dark.withValues(alpha: _kScrimAlpha),
      scrimMid: dark.withValues(alpha: _kScrimMidAlpha),
      scrimSoft: dark.withValues(alpha: _kScrimSoftAlpha),
      plate: dark.withValues(alpha: _kPlateAlpha),
      track: light.withValues(alpha: _kTrackAlpha),
      labelShadow: dark.withValues(alpha: _kLabelShadowAlpha),
      labelShadowStrong: dark.withValues(alpha: _kLabelShadowStrongAlpha),
    );
  }

  /// The opaque backdrop an image or video is letterboxed onto.
  final Color stage;

  /// Glyphs and labels that sit on a scrim, a plate, or the stage.
  final Color foreground;

  /// A secondary mark beside a primary one.
  final Color foregroundMuted;

  /// A control the user cannot act on.
  final Color foregroundDisabled;

  /// The edge gradient under the app bar, the toolbox, and the video controls.
  final Color scrim;

  /// The gradient's intermediate stop, where the band is nearly gone.
  final Color scrimMid;

  /// A wash over a whole frame or behind one round control.
  final Color scrimSoft;

  /// The solid plate behind a small on-image label.
  final Color plate;

  /// The unfilled remainder of a progress track drawn over artwork.
  final Color track;

  /// The text shadow that keeps a light label readable on a bright image.
  final Color labelShadow;

  /// The same shadow, weighted for coloured text.
  final Color labelShadowStrong;

  static AppMediaChrome of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppMediaChrome>() ??
        AppMediaChrome.from(theme.colorScheme);
  }

  @override
  AppMediaChrome copyWith({
    Color? stage,
    Color? foreground,
    Color? foregroundMuted,
    Color? foregroundDisabled,
    Color? scrim,
    Color? scrimMid,
    Color? scrimSoft,
    Color? plate,
    Color? track,
    Color? labelShadow,
    Color? labelShadowStrong,
  }) {
    return AppMediaChrome(
      stage: stage ?? this.stage,
      foreground: foreground ?? this.foreground,
      foregroundMuted: foregroundMuted ?? this.foregroundMuted,
      foregroundDisabled: foregroundDisabled ?? this.foregroundDisabled,
      scrim: scrim ?? this.scrim,
      scrimMid: scrimMid ?? this.scrimMid,
      scrimSoft: scrimSoft ?? this.scrimSoft,
      plate: plate ?? this.plate,
      track: track ?? this.track,
      labelShadow: labelShadow ?? this.labelShadow,
      labelShadowStrong: labelShadowStrong ?? this.labelShadowStrong,
    );
  }

  @override
  AppMediaChrome lerp(ThemeExtension<AppMediaChrome>? other, double t) {
    if (other is! AppMediaChrome) return this;
    return AppMediaChrome(
      stage: Color.lerp(stage, other.stage, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      foregroundMuted: Color.lerp(foregroundMuted, other.foregroundMuted, t)!,
      foregroundDisabled: Color.lerp(
        foregroundDisabled,
        other.foregroundDisabled,
        t,
      )!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      scrimMid: Color.lerp(scrimMid, other.scrimMid, t)!,
      scrimSoft: Color.lerp(scrimSoft, other.scrimSoft, t)!,
      plate: Color.lerp(plate, other.plate, t)!,
      track: Color.lerp(track, other.track, t)!,
      labelShadow: Color.lerp(labelShadow, other.labelShadow, t)!,
      labelShadowStrong: Color.lerp(
        labelShadowStrong,
        other.labelShadowStrong,
        t,
      )!,
    );
  }

  // ThemeData compares its extensions by value, so two identical builds have
  // to compare equal or MaterialApp restarts the theme cross-fade on every
  // unrelated root rebuild.
  @override
  bool operator ==(Object other) {
    return other is AppMediaChrome &&
        other.stage == stage &&
        other.foreground == foreground &&
        other.foregroundMuted == foregroundMuted &&
        other.foregroundDisabled == foregroundDisabled &&
        other.scrim == scrim &&
        other.scrimMid == scrimMid &&
        other.scrimSoft == scrimSoft &&
        other.plate == plate &&
        other.track == track &&
        other.labelShadow == labelShadow &&
        other.labelShadowStrong == labelShadowStrong;
  }

  @override
  int get hashCode => Object.hash(
    stage,
    foreground,
    foregroundMuted,
    foregroundDisabled,
    scrim,
    scrimMid,
    scrimSoft,
    plate,
    track,
    labelShadow,
    labelShadowStrong,
  );
}
