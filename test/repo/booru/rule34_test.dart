import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import '../../presentation/state/app_version_test.dart';
import '../../utils/dio.dart';
import '../../utils/hive.dart';
import '../../utils/mocktail.dart';
import '../../utils/riverpod.dart';

void main() async {
  setupLogger(test: true);
  setupMocktailFallbacks();
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Rule34', () async {
    final ref = ProviderContainer(
      overrides: [
        defaultServersProvider.overrideWithValue(await provideDefaultServers()),
        envRepoProvider.overrideWithValue(FakeEnvRepo()),
      ],
    );
    final hiveContainer = HiveTestContainer();

    addTearDown(() async {
      await hiveContainer.dispose();
      ref.dispose();
    });

    await UserServerRepo.prepare();
    ref.setupTestFor(dioProvider);
    final adapter = DioAdapterMock(ref.read(dioProvider));

    ref.setupTestFor(serverRepoProvider);
    await ref.read(serverRepoProvider).populate();

    final server = ref.read(serverRepoProvider).servers.getById('Rule34');
    // The homepage only serves the site; the API lives on its own host.
    expect(server.homepage, 'https://rule34.xxx');
    expect(server.apiAddr, 'https://api.rule34.xxx');

    ref.setupTestFor(imageboardRepoProvider(server));

    const option = PageOption(limit: 5);

    when(() => adapter.fetch(any(), any(), any())).thenAnswer(
      (_) async => FakeResponseBody.fromFixture('rule34/posts.xml', 200),
    );

    final posts = await ref
        .read(imageboardRepoProvider(server))
        .getPage(option, 1);
    expect(
      posts,
      isA<Iterable>().having((x) => x.length, 'total', option.limit),
    );

    final first = posts.first;
    expect(first.id, 19100840);
    expect(first.rateValue, 'e');
    expect(first.serverId, 'Rule34');
    expect(first.postUrl, startsWith('https://rule34.xxx/index.php?'));
    expect(first.previewFile, startsWith('https://api-cdn.rule34.xxx/'));

    when(() => adapter.fetch(any(), any(), any())).thenAnswer(
      (_) async =>
          FakeResponseBody.fromFixture('rule34/autocomplete.json', 200),
    );

    final suggestions = await ref
        .read(imageboardRepoProvider(server))
        .getSuggestion('land');
    expect(suggestions, hasLength(10));
    expect(
      suggestions.map((it) => it.name),
      containsAll(['landscape', 'landing_strip', 'lando']),
    );
    expect(
      suggestions.firstWhere((it) => it.name == 'landscape').count,
      4307,
      reason: 'the count rides in the label, not in its own field',
    );

    final requested =
        verify(() => adapter.fetch(captureAny(), any(), any())).captured.last
            as RequestOptions;
    expect(
      requested.uri.toString(),
      'https://api.rule34.xxx/autocomplete.php?q=land',
      reason: 'the dapi tag endpoint on this host asks for an account',
    );
  });
}
