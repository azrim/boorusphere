import 'dart:convert';

import 'package:boorusphere/data/dio/app_dio.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/web_clearance/web_clearance_repo.dart';
import 'package:boorusphere/domain/provider.dart';
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
