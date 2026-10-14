import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/screens/server/server_add_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/hive.dart';
import '../../state/app_version_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveTestContainer hiveContainer;

  setUpAll(() async {
    hiveContainer = HiveTestContainer();
    // `ServerAddPage` reads `uiSettingStateProvider`, which reads the
    // encrypted settings box.
    await UserSettingsRepo.prepare();
  });

  tearDownAll(() async {
    await hiveContainer.dispose();
  });

  Widget harness() {
    return ProviderScope(
      overrides: [envRepoProvider.overrideWithValue(FakeEnvRepo())],
      child: TranslationProvider(
        child: const MaterialApp(home: ServerAddPage()),
      ),
    );
  }

  testWidgets('defaults to Scan mode and hides the engine dropdown', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    // Scan is the default mode: the engine dropdown is gone and the scan
    // affordance is shown instead.
    expect(find.byType(DropdownButtonFormField<BooruEngine>), findsNothing);
    expect(find.text(t.servers.scanHint), findsOneWidget);
  });

  testWidgets('switching to Manual reveals the engine dropdown', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text(t.servers.mode.manual));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<BooruEngine>), findsOneWidget);
    expect(find.text(t.servers.scanHint), findsNothing);
  });
}
