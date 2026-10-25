import 'package:boorusphere/data/repository/env/fallback_env_repo.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const repo = FallbackEnvRepo();

  group('FallbackEnvRepo', () {
    test('reports the oldest SDK version', () {
      expect(repo.sdkVersion, 0);
      expect(repo.env.sdkVersion, 0);
    });

    test('reports a zero version that no stored version is older than', () {
      expect(repo.appVersion, AppVersion.zero);
      expect(repo.env.versionName, '0.0.0');
      expect(repo.env.versionCode, 0);
      expect(repo.appVersion.isNewerThan(AppVersion.zero), false);
      expect(
        repo.appVersion.isNewerThan(AppVersion.fromString('1.0.0')),
        false,
      );
    });
  });
}
