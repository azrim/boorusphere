import 'package:boorusphere/presentation/provider/app_theme.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

class AppThemeBuilder extends StatelessWidget {
  const AppThemeBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppThemeData appTheme) builder;

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (light, dark) =>
          builder(context, AppThemeData.from(light: light, dark: dark)),
    );
  }
}
