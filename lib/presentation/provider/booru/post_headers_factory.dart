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

/// The fields [postHeadersFactory] actually reads off a post.
///
/// Keying the provider family by the whole [Post] made every lookup hash all
/// five tag lists of a post (the Freezed equality compares them deeply) for a
/// value that only depends on two URLs.
typedef PostHeadersKey = ({String refererUrl, String mediaUrl});

PostHeadersKey postHeadersKeyOf(Post post) {
  return (
    refererUrl: post.postUrl.isEmpty ? post.content.url : post.postUrl,
    mediaUrl: post.content.url,
  );
}

@riverpod
Map<String, String> postHeadersFactory(
  Ref ref,
  PostHeadersKey key, {
  List<Cookie> cookies = const [],
}) {
  final versionRepo = ref.read(versionRepoProvider);
  final referer = createReferer(key.refererUrl);

  final headers = HeadersFactory.builder()
      .setCookies(cookies)
      .setReferer(referer)
      .setUserAgent(versionRepo.current)
      .build();

  // The file request goes to the CDN, which a challenged server guards with
  // the same clearance as the API. The cookie only counts when it arrives
  // with the agent that earned it, so both are taken from the same session.
  final media = Uri.tryParse(key.mediaUrl);
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
