import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/pigeon/app_env.pi.dart';

/// Environment answers for a run where the platform channel that reports them
/// is unavailable.
///
/// [sdkVersion] is 0 so every Android-version check takes its oldest branch:
/// no edge-to-edge layout, the legacy fullscreen handling and the plain
/// overlay style. [appVersion] is [AppVersion.zero], which is older than any
/// stored version, so the update prompt and the changelog stay closed while the
/// about screen and the drawer footer show 0.0.0.
class FallbackEnvRepo implements EnvRepo {
  const FallbackEnvRepo();

  @override
  Env get env => Env(
    versionName: AppVersion.zero.toString(),
    versionCode: 0,
    sdkVersion: 0,
  );

  @override
  int get sdkVersion => 0;

  @override
  AppVersion get appVersion => AppVersion.zero;
}
