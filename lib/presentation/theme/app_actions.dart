import 'package:boorusphere/presentation/theme/contrast.dart';
import 'package:flutter/material.dart';

/// Accents lifted to read as text on a raised surface.
///
/// A scheme's `primary` and `error` are guaranteed against the page. A toast,
/// a dialog, a sheet, a selected row or a block sits one or more tones above
/// it, and the same accent can drop below 4.5:1 there. The highest container
/// tone is the extreme of the ramp, so an accent that clears it clears the
/// page and every block in between; one pair then serves every raised surface
/// without moving the fills, which keep the palette's own accent.
@immutable
class AppActionRoles extends ThemeExtension<AppActionRoles> {
  const AppActionRoles({required this.primary, required this.error});

  factory AppActionRoles.from(ColorScheme scheme) {
    final raised = [scheme.surfaceContainerHighest];
    return AppActionRoles(
      primary: readableOnSurfaces(scheme.primary, raised),
      error: readableOnSurfaces(scheme.error, raised),
    );
  }

  /// The accent for an action painted on a block, a dialog or a chip.
  final Color primary;

  /// The destructive ink for a block, a dialog or a chip.
  final Color error;

  static AppActionRoles of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppActionRoles>() ??
        AppActionRoles.from(theme.colorScheme);
  }

  @override
  AppActionRoles copyWith({Color? primary, Color? error}) {
    return AppActionRoles(
      primary: primary ?? this.primary,
      error: error ?? this.error,
    );
  }

  @override
  AppActionRoles lerp(ThemeExtension<AppActionRoles>? other, double t) {
    if (other is! AppActionRoles) return this;
    return AppActionRoles(
      primary: Color.lerp(primary, other.primary, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppActionRoles &&
        other.primary == primary &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(primary, error);
}
