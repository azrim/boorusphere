import 'dart:io';

import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/utils/http/cookies.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'post_headers_factory.g.dart';

String createReferer(String url) {
  final uri = Uri.parse(url);
  final path = uri.path.replaceAll(RegExp('/+'), '/');
  return uri.replace(path: uri.hasAbsolutePath ? path : '/').toString();
}

@riverpod
Map<String, String> postHeadersFactory(
  Ref ref,
  Post post, {
  List<Cookie> cookies = const [],
}) {
  final versionRepo = ref.read(versionRepoProvider);
  final url = post.postUrl.isEmpty ? post.content.url : post.postUrl;
  final referer = createReferer(url);

  final headers = HeadersFactory.builder()
      .setCookies(cookies)
      .setReferer(referer)
      .setUserAgent(versionRepo.current)
      .build();

  // The file request goes to the CDN, which a challenged server guards with
  // the same clearance as the API. The cookie only counts when it arrives
  // with the agent that earned it, so both are taken from the same session.
  final media = Uri.tryParse(post.content.url);
  final clearance = media == null
      ? null
      : ref.watch(webClearanceRepoProvider).forHost(media.host);
  if (clearance != null) {
    headers[HttpHeaders.userAgentHeader] = clearance.userAgent;
    final merged = mergeCookieHeaders(
      headers[HttpHeaders.cookieHeader],
      clearance.cookies,
    );
    if (merged.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = merged;
    }
  }

  return headers;
}
