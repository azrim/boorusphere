import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/screens/settings/gesture_settings_page.dart';
import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../state/app_version_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The row's choice has to reach storage, but a real settings box would put
  // that write behind file I/O the fake-async test clock never lets finish:
  // the future stays pending when the test ends, and the box close in teardown
  // then waits on it forever. The in-memory repo is the same repo with only
  // persistence missing, and persistence is what the state tests cover.
  final settings = UserSettingsRepo(null);

  Widget harness() {
    return ProviderScope(
      overrides: [
        envRepoProvider.overrideWithValue(FakeEnvRepo()),
        settingsRepoProvider.overrideWithValue(settings),
      ],
      child: TranslationProvider(
        child: const MaterialApp(home: GestureSettingsPage()),
      ),
    );
  }

  group('GestureSettingsPage', () {
    testWidgets('the swipe mode is a row that opens a sheet', (tester) async {
      await tester.pumpWidget(harness());

      expect(find.text(t.settingsPage.horizontal), findsOneWidget);
      // Two radio rows were the only pair of their kind in settings; a value
      // out of a short list is asked for in a sheet here as well.
      expect(find.byType(RadioListTile<SwipeMode>), findsNothing);

      // The label is where a reader looks, so the row has to answer there: the
      // old row was tappable only inside a small control at the edge.
      await tester.tap(find.text(t.settingsPage.horizontal));
      await tester.pumpAndSettle();

      expect(find.text(t.settingsPage.vertical), findsOneWidget);
      expect(find.text(t.settingsPage.verticalDesc), findsOneWidget);

      await tester.tap(find.text(t.settingsPage.vertical));
      await tester.pumpAndSettle();

      // The sheet is gone and the row states the mode that was chosen.
      expect(find.text(t.settingsPage.vertical), findsOneWidget);
      expect(find.text(t.settingsPage.horizontal), findsNothing);

      // And the choice was written, not only shown: the row and the storage
      // agree on the mode.
      expect(
        settings.get(Setting.gestureSwipeMode, or: 'horizontal'),
        'vertical',
      );
    });
  });
}
