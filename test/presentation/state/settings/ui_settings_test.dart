import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/hive.dart';
import '../../../utils/riverpod.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UiSetting', () {
    final ref = ProviderContainer();
    final hiveContainer = HiveTestContainer();

    notifier() => ref.read(uiSettingStateProvider.notifier);
    state() => ref.read(uiSettingStateProvider);

    setUpAll(() async {
      await UserSettingsRepo.prepare();
      ref.setupTestFor(uiSettingStateProvider);
    });

    tearDownAll(() async {
      await hiveContainer.dispose();
      ref.dispose();
    });

    test('blur', () async {
      await notifier().showBlur(false);

      expect(state().blur, false);
    });

    test('grid', () async {
      final initial = state().grid;
      await notifier().cycleGrid();

      expect(state().grid, initial + 1);
    });

    test('locale', () async {
      await notifier().setLocale(AppLocale.idId);
      expect(state().locale, AppLocale.idId);
      expect(LocaleSettings.currentLocale, AppLocale.idId);
    });

    test('base locale', () async {
      await notifier().setLocale(null);
      expect(state().locale, null);
      expect(LocaleSettings.currentLocale, AppLocale.en);
    });

    test('cycle themeMode', () async {
      await notifier().setThemeMode(ThemeMode.light);

      await notifier().cycleThemeMode();
      expect(state().themeMode, ThemeMode.system);
      await notifier().cycleThemeMode();
      expect(state().themeMode, ThemeMode.dark);
      await notifier().cycleThemeMode();
      expect(state().themeMode, ThemeMode.light);
    });

    test('midnightMode', () async {
      await notifier().setMidnightMode(true);

      expect(state().midnightMode, true);
    });

    test('imeIncognito', () async {
      await notifier().setImeIncognito(true);

      expect(state().imeIncognito, true);
    });

    test('colorPalette', () async {
      await notifier().setColorPalette(ColorPalette.dracula);

      expect(state().colorPalette, ColorPalette.dracula);
    });

    test('colorPalette survives a reload', () async {
      await notifier().setColorPalette(ColorPalette.gruvbox);

      final box = Hive.box(UserSettingsRepo.key);
      await box.flush();
      await box.close();
      await UserSettingsRepo.prepare();

      final reloaded = UserSettingsRepo(
        Hive.box(UserSettingsRepo.key),
      ).get(Setting.uiColorPalette, or: ColorPalette.system.name);
      expect(ColorPalette.fromName(reloaded), ColorPalette.gruvbox);
    });
  });
}
