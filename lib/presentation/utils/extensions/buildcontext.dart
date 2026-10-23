import 'package:flutter/material.dart';

extension BuildContextExt on BuildContext {
  ThemeData get theme => Theme.of(this);
  NavigatorState get navigator => Navigator.of(this);

  /// Subscribes to all aspects of MediaQuery. Prefer the aspect-scoped
  /// accessors below ([mqSize], [mqPadding], [mqViewPadding], [mqViewInsets],
  /// [mqDpr]) when only one aspect is needed; they avoid invalidation on
  /// unrelated MediaQuery changes (keyboard, rotation, etc.).
  MediaQueryData get mediaQuery => MediaQuery.of(this);

  Size get mqSize => MediaQuery.sizeOf(this);
  EdgeInsets get mqPadding => MediaQuery.paddingOf(this);
  EdgeInsets get mqViewPadding => MediaQuery.viewPaddingOf(this);
  EdgeInsets get mqViewInsets => MediaQuery.viewInsetsOf(this);
  double get mqDpr => MediaQuery.devicePixelRatioOf(this);

  ScaffoldMessengerState get scaffoldMessenger => ScaffoldMessenger.of(this);
  IconThemeData get iconTheme => IconTheme.of(this);

  Brightness get brightness => theme.brightness;
  ColorScheme get colorScheme => theme.colorScheme;
  bool get isDarkThemed => brightness == Brightness.dark;
  bool get isLightThemed => brightness == Brightness.light;

  /// Whether the platform asks for reduced motion ("Remove animations" on
  /// Android, Reduce Motion on iOS). Transitions that only translate or scale
  /// should collapse to an instant change; a short fade may stay, because it
  /// still communicates the state change without moving the view.
  bool get reducedMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// [duration], or zero when [reducedMotion] is set. Use it for movement;
  /// keep a short explicit duration for opacity fades.
  Duration motionDuration(Duration duration) =>
      reducedMotion ? Duration.zero : duration;
}
