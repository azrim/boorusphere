import 'package:flutter/material.dart';

/// How a theme wants its surfaces to read.
///
/// Two themes can both be dark and still want different depth: Night lifts a
/// block off the page with a container tone, while Midnight paints the page
/// black on purpose and lets a hairline do the separating. The flag lives on
/// the theme so a widget asks the policy instead of guessing from brightness.
@immutable
class AppSurfacePolicy extends ThemeExtension<AppSurfacePolicy> {
  const AppSurfacePolicy({required this.flat});

  /// True when surfaces stay on the page tone and only hairlines separate
  /// them — the Midnight rule.
  final bool flat;

  static AppSurfacePolicy of(BuildContext context) {
    return Theme.of(context).extension<AppSurfacePolicy>() ??
        const AppSurfacePolicy(flat: false);
  }

  @override
  AppSurfacePolicy copyWith({bool? flat}) {
    return AppSurfacePolicy(flat: flat ?? this.flat);
  }

  @override
  AppSurfacePolicy lerp(ThemeExtension<AppSurfacePolicy>? other, double t) {
    if (other is! AppSurfacePolicy) return this;
    return t < 0.5 ? this : other;
  }
}
