import 'dart:io';

import 'package:boorusphere/utils/logger.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

class DeviceWorkarounds {
  const DeviceWorkarounds._();

  static Future<Map<String, String>> get buildProps async {
    try {
      final getProp = await Process.run('getprop', []);
      return Map.fromEntries(
        getProp.stdout
            .toString()
            .split('\n')
            .where((x) => x.startsWith('[') && x.endsWith(']'))
            .map((e) => e.replaceAll(RegExp(r'(^\[|\]$)'), '').split(']: ['))
            .map((x) => MapEntry(x.first, x.last))
            .where((x) => x.value.isNotEmpty),
      );
    } catch (e, s) {
      mainLog.e('Failed to get device prop', e, s);
      return {};
    }
  }

  static isOppo(Map<String, String> props) {
    final brand = [
      'ro.product.brand',
      'ro.product.system.brand',
      'ro.product.system_ext.brand',
      'ro.product.vendor.brand',
    ].map((x) => props[x]?.toLowerCase()).nonNulls;
    final oppo = ['oppo', 'oplus', 'oneplus', 'realme']; // same shit

    return oppo.any(brand.contains);
  }

  // ignore: avoid_void_async
  static void apply() async {
    if (!Platform.isAndroid) return;

    // Opt every Android device into the highest available display mode.
    // Without this call, phones that natively support 90/120 Hz panels run
    // the Flutter engine at 60 Hz, halving perceived smoothness.
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e, s) {
      mainLog.w('Failed to set high refresh rate', e, s);
    }

    final props = await buildProps;
    if (isOppo(props)) {
      // OPPO/OnePlus/Realme/OPlus skins regress to 60 Hz after navigation
      // events. Re-apply once props are known so the workaround sticks.
      mainLog.i('Re-applying highest refresh rate on OPPO-family device');
      try {
        await FlutterDisplayMode.setHighRefreshRate();
      } catch (e, s) {
        mainLog.w('Failed to re-apply high refresh rate', e, s);
      }
    }
  }
}
