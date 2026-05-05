//
// Script for renaming apks for release purposes
//

import 'dart:developer';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Maps the variant slug in the final APK filename to the source APK filename
/// emitted by `flutter build apk`.
///
/// `--split-per-abi` produces `app-<abi>-release.apk` for each ABI; a plain
/// `flutter build apk` produces a single `app-release.apk` containing every
/// ABI (the "universal" build).
const Map<String, String> _variantSources = {
  'arm64-v8a': 'app-arm64-v8a-release.apk',
  'armeabi-v7a': 'app-armeabi-v7a-release.apk',
  'x86_64': 'app-x86_64-release.apk',
  'universal': 'app-release.apk',
};

String get _outputDir {
  return path.normalize(
    path.join(Directory.current.path, 'build/app/outputs/flutter-apk'),
  );
}

YamlMap get _pubspec {
  final yamlPath = path.normalize(
    path.join(Directory.current.path, 'pubspec.yaml'),
  );
  final content = File(yamlPath).readAsStringSync();
  return loadYaml(content);
}

String get _appVersion {
  return _pubspec['version'];
}

String get _appVersionName {
  return _appVersion.split('+').first;
}

Future<void> _renameOutputApks(
  String outDir, {
  required String from,
  required String to,
}) async {
  final fromPath = path.normalize(path.join(outDir, from));
  final toPath = path.normalize(path.join(outDir, to));
  final apk = File(fromPath);
  if (apk.existsSync()) {
    log(':: Renaming $from to $to');
    await apk.rename(toPath);
  }
}

void main() async {
  if (!Directory(_outputDir).existsSync()) {
    throw FileSystemException('Directory is not exists', _outputDir);
  }

  await Future.wait([
    for (final entry in _variantSources.entries)
      _renameOutputApks(
        _outputDir,
        from: entry.value,
        to: 'boorusphere-$_appVersionName-${entry.key}.apk',
      ),
  ]);
}
