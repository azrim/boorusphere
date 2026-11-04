import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/data/dio/app_dio.dart';
import 'package:boorusphere/data/repository/app_lock/secure_app_lock_repo.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/video_cache/video_cache.dart';
import 'package:boorusphere/data/repository/web_clearance/web_clearance_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/app_lock_repo.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

@Riverpod(keepAlive: true)
CookieJar cookieJar(Ref ref) {
  return CookieJar();
}

Future<CookieJar> provideCookieJar() async {
  final dir = await getApplicationDocumentsDirectory();
  return PersistCookieJar(storage: FileStorage(path.join(dir.path, 'cookies')));
}

@Riverpod(keepAlive: true)
Map<String, Server> defaultServers(Ref ref) {
  return {};
}

Future<Map<String, Server>> provideDefaultServers() async {
  final json = await rootBundle.loadString('assets/servers.json');
  final servers = jsonDecode(json) as List;
  return Map.fromEntries(
    servers.map((it) {
      final value = Server.fromJson(it);
      return MapEntry(value.key, value);
    }),
  );
}

/// Kept alive for the whole session: every request goes through this client,
/// and a client per fetch would drop the HTTP connection pool (a fresh TLS
/// handshake per page) and leave its sockets to the garbage collector.
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final cookieJar = ref.watch(cookieJarProvider);
  final envRepo = ref.watch(envRepoProvider);
  final clearance = ref.watch(webClearanceRepoProvider);
  final client = AppDio(
    cookieJar: cookieJar,
    envRepo: envRepo,
    clearance: clearance,
  );
  ref.onDispose(() => client.close(force: true));
  return client;
}

/// The clearances solved in the in-app browser, read on every request.
@Riverpod(keepAlive: true)
WebClearanceRepo webClearanceRepo(Ref ref) {
  return WebClearanceRepo.open();
}

/// The disk cache videos are replayed from.
///
/// Kept alive so the index and the background downloads survive a page change,
/// and so clearing it from the settings empties the same instance the player
/// reads from.
@Riverpod(keepAlive: true)
VideoCache videoCache(Ref ref) {
  final client = ref.watch(dioProvider);
  final settings = ref.watch(settingsRepoProvider);
  return VideoCache(
    client: client,
    directory: () async {
      final root = await getApplicationCacheDirectory();
      return Directory(path.join(root.path, 'videos'));
    },
    maxBytes: VideoCache.budgetFrom(
      settings.get(Setting.videoCacheMaxBytes, or: VideoCache.defaultMaxBytes),
    ),
  );
}

/// The PIN verifier and lock preferences, read from secure storage at boot.
///
/// Kept alive so every screen sees the same in-memory copy after a write, and
/// overridden in [main] with the instance boot already had to read.
@Riverpod(keepAlive: true)
AppLockRepo appLockRepo(Ref ref) {
  throw UnimplementedError('must be initialized manually');
}

Future<AppLockRepo> provideAppLockRepo() {
  return SecureAppLockRepo.open();
}
