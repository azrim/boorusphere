import 'package:boorusphere/constant/app.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/domain/repository/version_repo.dart';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

final _log = Logger('AppVersionRepo');

class AppVersionRepo implements VersionRepo {
  AppVersionRepo({required this.envRepo, required this.client});

  final EnvRepo envRepo;
  final Dio client;

  @override
  AppVersion get current => envRepo.appVersion;

  /// Resolve the latest available app version.
  ///
  /// Prefers the GitHub Releases API over `raw/main/pubspec.yaml`
  /// because `pubspec.yaml` on `main` advertises the new version as
  /// soon as the version-bump commit lands, which happens BEFORE the
  /// `Build APK` workflow uploads the corresponding APK assets to the
  /// matching GitHub Release. During that ~10 min build window, the
  /// pubspec-only path used to advertise version X and then 404 on
  /// downloading X's APK (user report after v2.0.15).
  ///
  /// The Releases API is the source of truth: a release only exists
  /// once `softprops/action-gh-release` has uploaded the APK assets at
  /// the very end of `Build APK`, so anything `releases/latest`
  /// returns is guaranteed to have a downloadable APK for some arch.
  /// We additionally verify the running architecture's APK is in the
  /// release's asset list — defends against partial uploads (network
  /// hiccup mid-upload, runner timeout, etc.).
  ///
  /// `pubspec.yaml` fallback only kicks in when the API call **errors**
  /// (network failure, DNS, rate limit). If the API responds but the
  /// response doesn't contain a usable release/asset, we return
  /// [AppVersion.zero] rather than fall back to pubspec — falling back
  /// would re-introduce the original race we're trying to avoid.
  @override
  Future<AppVersion> fetch() async {
    try {
      final res = await client.get(_latestReleaseUrl);
      if (res.statusCode == 200) {
        return _parseReleaseResponse(res.data) ?? AppVersion.zero;
      }
    } catch (e) {
      _log.warning('Version fetch failed: $e');
      // Fall through to pubspec fallback below.
    }
    try {
      final res = await client.get(pubspecUrl);
      if (res.statusCode == 200) {
        return _parsePubspecResponse(res.data) ?? AppVersion.zero;
      }
    } catch (e) {
      _log.warning('Version fetch failed: $e');
      // Fall through to zero.
    }
    return AppVersion.zero;
  }

  AppVersion? _parseReleaseResponse(Object? data) {
    if (data is! Map) return null;
    final tagName = data['tag_name'];
    if (tagName is! String || !tagName.startsWith('v')) return null;
    final version = AppVersion.fromString(tagName.substring(1));
    final assets = data['assets'];
    if (assets is! List) return null;
    final expectedAssetName = 'boorusphere-$version-$kAppArch.apk';
    final hasMatchingAsset = assets.any(
      (a) => a is Map && a['name'] == expectedAssetName,
    );
    if (!hasMatchingAsset) return null;
    return version;
  }

  AppVersion? _parsePubspecResponse(Object? data) {
    if (data is! String || !data.contains('version:')) return null;
    final version = loadYaml(data)['version'];
    if (version is! String || !version.contains('+')) return null;
    return AppVersion.fromString(version);
  }

  static const gitUrl = 'https://github.com/azrim/boorusphere';
  static const pubspecUrl = '$gitUrl/raw/main/pubspec.yaml';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/azrim/boorusphere/releases/latest';
}
