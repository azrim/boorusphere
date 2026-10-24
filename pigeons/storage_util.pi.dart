import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/pigeon/storage_util.pi.dart',
    kotlinOut:
        'android/app/src/main/kotlin/io/chaldeaprjkt/boorusphere/pigeon/StorageUtil.pi.kt',
    kotlinOptions: KotlinOptions(errorClassName: 'StorageUtilException'),
  ),
)
@HostApi()
abstract class StorageUtil {
  String getStoragePath();
  String getDownloadPath();
  void open(String filePath);
  void shareText(String text, String? subject);

  /// Asks the media scanner to index [path] (a file or a directory) so it
  /// shows up in the gallery and in other apps.
  void scanMedia(String path);
}
