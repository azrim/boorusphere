import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/pigeon/app_env.pi.dart',
    kotlinOut:
        'android/app/src/main/kotlin/io/chaldeaprjkt/boorusphere/pigeon/AppEnv.pi.kt',
    kotlinOptions: KotlinOptions(errorClassName: 'AppEnvException'),
  ),
)
@HostApi()
abstract class AppEnv {
  Env get();

  /// Closes the app by finishing its activity, for the restart a restore
  /// requires. A back request cannot do it: the dialog that asks for the
  /// restart holds back handling, so the request would be swallowed by the
  /// dialog that made it.
  void exitApp();
}

class Env {
  Env({
    required this.versionName,
    required this.versionCode,
    required this.sdkVersion,
  });

  final String versionName;
  final int versionCode;
  final int sdkVersion;
}
