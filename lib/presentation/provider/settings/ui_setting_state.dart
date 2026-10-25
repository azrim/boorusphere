import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ui_setting_state.g.dart';

@riverpod
class UiSettingState extends _$UiSettingState {
  @override
  UiSetting build() {
    final repo = ref.read(settingsRepoProvider);
    return UiSetting(
      blur: repo.get(Setting.uiBlur, or: true),
      grid: repo.get(Setting.uiTimelineGrid, or: 1),
      locale: localeFromStr(repo.get(Setting.uiLanguage, or: '')),
      themeMode: _themeModeFrom(
        repo.get<Object>(Setting.uiThemeMode, or: ThemeMode.system.name),
      ),
      midnightMode: repo.get(Setting.uiMidnightMode, or: false),
      imeIncognito: repo.get(Setting.imeIncognito, or: false),
      colorPalette: ColorPalette.fromName(
        repo.get(Setting.uiColorPalette, or: ColorPalette.system.name),
      ),
    );
  }

  /// Reads the stored theme mode. A name is what this build writes, so a
  /// reordered [ThemeMode] keeps its meaning; an index is what an older build
  /// left behind, and is still read the way that build wrote it.
  ThemeMode _themeModeFrom(Object stored) {
    if (stored is int) {
      return ThemeMode.values.elementAtOrNull(stored) ?? ThemeMode.system;
    }
    return ThemeMode.values.firstWhere(
      (it) => it.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<int> cycleGrid() async {
    state = state.copyWith(grid: state.grid < 2 ? state.grid + 1 : 0);
    final repo = ref.read(settingsRepoProvider);

    await repo.put(Setting.uiTimelineGrid, state.grid);
    return state.grid;
  }

  Future<bool> showBlur(bool value) async {
    state = state.copyWith(blur: value);
    final repo = ref.read(settingsRepoProvider);

    await repo.put(Setting.uiBlur, value);
    return state.blur;
  }

  AppLocale? localeFromStr(String name) {
    try {
      return AppLocale.values.firstWhere((it) => it.name == name);
    } on StateError {
      return null;
    }
  }

  Future<AppLocale?> setLocale(AppLocale? locale) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(locale: locale);
    if (locale == null) {
      LocaleSettings.useDeviceLocaleSync();
    } else {
      LocaleSettings.setLocaleSync(locale);
    }

    await repo.put(Setting.uiLanguage, locale == null ? '' : locale.name);
    return state.locale;
  }

  Future<ThemeMode> setThemeMode(ThemeMode mode) async {
    final repo = ref.read(settingsRepoProvider);

    state = state.copyWith(themeMode: mode);
    await repo.put(Setting.uiThemeMode, mode.name);
    return state.themeMode;
  }

  Future<ThemeMode> cycleThemeMode() async {
    switch (state.themeMode) {
      case ThemeMode.dark:
        await setThemeMode(ThemeMode.light);
        break;
      case ThemeMode.light:
        await setThemeMode(ThemeMode.system);
        break;
      default:
        await setThemeMode(ThemeMode.dark);
        break;
    }
    return state.themeMode;
  }

  Future<bool> setMidnightMode(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(midnightMode: value);
    await repo.put(Setting.uiMidnightMode, value);
    return state.midnightMode;
  }

  Future<bool> setImeIncognito(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(imeIncognito: value);
    await repo.put(Setting.imeIncognito, value);
    return state.imeIncognito;
  }

  Future<ColorPalette> setColorPalette(ColorPalette palette) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(colorPalette: palette);
    await repo.put(Setting.uiColorPalette, palette.name);
    return state.colorPalette;
  }
}
