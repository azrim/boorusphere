import 'package:boorusphere/presentation/provider/app_theme.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AppThemeBuilder extends HookConsumerWidget {
  const AppThemeBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppThemeData appTheme) builder;

  @override
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorPalette = ref.watch(uiSettingStateProvider).colorPalette;

    return DynamicColorBuilder(
      builder: (light, dark) => builder(
        context,
        AppThemeData.from(light: light, dark: dark, colorPalette: colorPalette),
      ),
    );
  }
}
