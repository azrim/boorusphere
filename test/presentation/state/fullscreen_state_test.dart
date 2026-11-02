import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import '../../utils/riverpod.dart';

class MockEnvRepo extends Mock implements EnvRepo {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockEnvRepo envRepo;
  late ProviderContainer ref;
  late List<MethodCall> platformCalls;

  setUp(() {
    envRepo = MockEnvRepo();
    when(() => envRepo.sdkVersion).thenReturn(33);

    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });

    ref = ProviderContainer(
      overrides: [envRepoProvider.overrideWithValue(envRepo)],
    );
    ref.setupTestFor(fullscreenStateProvider);
  });

  tearDown(() {
    ref.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  FullscreenState notifier() => ref.read(fullscreenStateProvider.notifier);
  bool state() => ref.read(fullscreenStateProvider);

  test('toggle enters immersive mode', () async {
    await notifier().toggle();

    expect(state(), true);
    expect(
      platformCalls.map((call) => call.method),
      contains('SystemChrome.setEnabledSystemUIMode'),
    );
  });

  test('reset drops the flag as well as the platform state', () async {
    await notifier().toggle();
    platformCalls.clear();

    notifier().reset();

    // The viewer is non-opaque and can stay mounted under a pushed route, and
    // a viewer pushed from that route reads this same flag. Leaving state at
    // true would open it fullscreen while the bars are back on screen.
    expect(state(), false);
    expect(
      platformCalls.map((call) => call.method),
      containsAll([
        'SystemChrome.setPreferredOrientations',
        'SystemChrome.setEnabledSystemUIMode',
      ]),
    );
    expect(
      platformCalls
          .where((call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
          .map((call) => call.arguments),
      contains('SystemUiMode.edgeToEdge'),
    );
  });
}
