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
}
