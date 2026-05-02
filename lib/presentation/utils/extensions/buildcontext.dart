import 'package:flutter/material.dart';

extension BuildContextExt on BuildContext {
  ThemeData get theme => Theme.of(this);
  NavigatorState get navigator => Navigator.of(this);

  /// Subscribes to every MediaQuery field. Prefer the scoped accessors
  /// below (screenSize, viewPadding, devicePixelRatio, etc.) to avoid
  /// rebuilding on unrelated changes (e.g. keyboard, orientation).
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  ScaffoldMessengerState get scaffoldMessenger => ScaffoldMessenger.of(this);
  IconThemeData get iconTheme => IconTheme.of(this);

  // Scoped MediaQuery accessors — each only rebuilds the consumer when
  // *that specific* field changes.
  Size get screenSize => MediaQuery.sizeOf(this);
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);
  EdgeInsets get padding => MediaQuery.paddingOf(this);
  EdgeInsets get viewInsets => MediaQuery.viewInsetsOf(this);
  double get devicePixelRatio => MediaQuery.devicePixelRatioOf(this);
  Orientation get orientation => MediaQuery.orientationOf(this);

  Brightness get brightness => theme.brightness;
  ColorScheme get colorScheme => theme.colorScheme;
  bool get isDarkThemed => brightness == Brightness.dark;
  bool get isLightThemed => brightness == Brightness.light;
}
