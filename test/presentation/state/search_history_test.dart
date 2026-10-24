import 'package:boorusphere/data/repository/search_history/user_search_history.dart';
import 'package:boorusphere/presentation/provider/search_history_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../utils/fake_data.dart';
import '../../utils/hive.dart';
import '../../utils/riverpod.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('search history', () {
    final servers = getDefaultServerData();
    final ref = ProviderContainer();
    final hiveContainer = HiveTestContainer();

    notifier() => ref.read(searchHistoryStateProvider.notifier);
    state() => ref.read(searchHistoryStateProvider);

    setUpAll(() async {
      await UserSearchHistoryRepo.prepare();
      ref.setupTestFor(searchHistoryStateProvider);
    });

    tearDownAll(() async {
      await hiveContainer.dispose();
      ref.dispose();
    });

    test('push', () async {
      final tags = ['foo', 'bar', 'baz'];
      for (var tag in tags) {
        await notifier().save(tag, servers.first);
      }
      expect(state().length, 3);
    });

    test('filter', () {
      expect(ref.read(filterHistoryProvider('o')).values.first.query, 'foo');
      expect(ref.read(filterHistoryProvider('r')).values.first.query, 'bar');
      expect(ref.read(filterHistoryProvider('z')).values.first.query, 'baz');
      expect(ref.read(filterHistoryProvider('m')).length, 0);
    });

    test('remove last', () async {
      await notifier().delete(state().keys.last);
      expect(state().length, 2);
    });

    test('filter ranks the closest match above older entries', () async {
      await notifier().clear();
      // Saved oldest first, so recency alone would leave the exact tag last.
      await notifier().save('anime_screenshot', servers.first);
      await notifier().save('futaba_rio anime_screenshot', servers.first);
      await notifier().save('naruto_(series) anime_screenshot', servers.first);

      final filtered = ref.read(filterHistoryProvider('anime'));

      expect(filtered.values.first.query, 'anime_screenshot');
      expect(filtered.length, 3);
    });

    test('cleanup', () async {
      await notifier().clear();
      expect(state().length, 0);
    });
  });
}
