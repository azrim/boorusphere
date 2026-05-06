import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'ui_setting.freezed.dart';

/// Color palette presets for theme accent colors
enum ColorPalette {
  system(null, 'System'),
  dracula(Color.fromARGB(255, 189, 147, 249), 'Dracula'),
  catpuccin(Color.fromARGB(255, 198, 160, 246), 'Catpuccin'),
  nord(Color.fromARGB(255, 136, 192, 208), 'Nord'),
  solarized(Color.fromARGB(255, 211, 54, 130), 'Solarized'),
  gruvbox(Color.fromARGB(255, 204, 153, 117), 'Gruvbox'),
  oneDark(Color.fromARGB(255, 97, 175, 239), 'One Dark'),
  monokai(Color.fromARGB(255, 249, 38, 114), 'Monokai'),
  github(Color.fromARGB(255, 3, 131, 240), 'GitHub'),
  materialYou(Color.fromARGB(255, 149, 30, 229), 'Material You');

  const ColorPalette(this.accentColor, this.displayName);

  final Color? accentColor;
  final String displayName;
}

@freezed
class UiSetting with _$UiSetting {
  const factory UiSetting({
    @Default(true) bool blur,
    @Default(1) int grid,
    AppLocale? locale,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(false) bool midnightMode,
    @Default(false) bool imeIncognito,
    @Default(ColorPalette.system) ColorPalette colorPalette,
  }) = _UiSetting;
}
