import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/entity/page_data.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/strings.dart';
import 'package:boorusphere/presentation/widgets/error_info.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline.dart';
import 'package:boorusphere/utils/http/auth_error.dart';
import 'package:boorusphere/utils/http/cloudflare.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

class HomeStatus extends HookConsumerWidget {
  const HomeStatus({super.key, this.skeletonWhenLoading = true});

  /// Whether a fetch in flight should show the placeholder grid. Infinite mode
  /// keeps the loaded posts on screen and reports the append inline instead.
  final bool skeletonWhenLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(pageStateProvider);

    return switch (pageState) {
      IdleFetchResult() || DataFetchResult() => const SizedBox.shrink(),
      LoadingFetchResult() =>
        skeletonWhenLoading
            ? const TimelineSkeleton()
            : const SizedBox.shrink(),
      ErrorFetchResult(:final data, :final error, :final stackTrace) =>
        _ErrorStatus(data: data, error: error, stackTrace: stackTrace),
    };
  }
}

/// The page-aware reading of a failed request: a status code, a challenge or
/// a blocked query names what the reader can do about it.
Object? buildPageStatusError(
  BuildContext context,
  PageData data,
  Object? error,
  Server server,
) {
  final e = error;
  if (isCloudflareChallenge(e)) {
    // Not a rejection of the query: the server never read it. The status
    // code would read as the server's answer, so the line says what the
    // check is and the card offers the browser that can answer it.
    return context.t.pageStatus.cloudflareChallenge(serverName: server.name);
  } else if (isAuthRequired(e)) {
    // The server would answer a signed request. Naming the missing
    // credentials beats reporting a status code the reader cannot act on.
    return context.t.pageStatus.unauthorized(serverName: server.name);
  } else if (e is DioException && e.response?.statusCode != null) {
    // A bare status code leaves the reader guessing whether the account, the
    // query or the rate limit is at fault; each of these names the fix.
    return switch (e.response!.statusCode) {
      401 => context.t.pageStatus.unauthorized(serverName: server.name),
      403 => context.t.pageStatus.forbidden(serverName: server.name),
      429 => context.t.pageStatus.rateLimited(serverName: server.name),
      _ =>
        context.t.pageStatus
            .httpError(serverName: server.name)
            .withDioExceptionCode(e),
    };
  } else if (e == BooruError.empty) {
    return data.option.query.isEmpty
        ? context.t.pageStatus.noResult(n: data.posts.length)
        : context.t.pageStatus.noResultForQuery(
            n: data.posts.length,
            query: data.option.query,
          );
  } else if (e == BooruError.filtered) {
    // The query has results; the local filters hid the page. Naming the filter
    // beats reporting an empty result the reader would try to search around.
    return context.t.pageStatus.filteredEmpty;
  } else if (e == BooruError.tagsBlocked) {
    return context.t.pageStatus.blocked(query: data.option.query);
  } else if (e == BooruError.unparsable) {
    return context.t.pageStatus.unparsable(serverName: server.name);
  } else {
    return e;
  }
}

/// The same reading as one line, for the surfaces that cannot show the card:
/// a failed page step while the grid is already showing posts has no room for
/// a notice below the fold.
String describePageStatus(
  BuildContext context,
  PageData data,
  Object? error,
  Server server,
) {
  final message = buildPageStatusError(context, data, error, server);
  return message is String ? message : describeError(context, message);
}

class _ErrorStatus extends ConsumerWidget {
  const _ErrorStatus({required this.data, this.error, this.stackTrace});

  final PageData data;
  final Object? error;
  final StackTrace? stackTrace;

  Icon _getIconForError(Object? error) {
    if (isCloudflareChallenge(error)) {
      return const Icon(Icons.shield_outlined);
    } else if (isAuthRequired(error)) {
      return const Icon(Icons.key_outlined);
    } else if (error is DioException) {
      return const Icon(Icons.wifi_off);
    } else if (error == BooruError.empty) {
      return const Icon(Icons.explore_off);
    } else if (error == BooruError.filtered) {
      return const Icon(Icons.filter_alt_off_outlined);
    } else if (error == BooruError.tagsBlocked) {
      return const Icon(Icons.block);
    } else if (error == BooruError.unparsable) {
      return const Icon(Icons.help_outline);
    }
    return const Icon(Icons.error_outline);
  }

  /// Opens the built-in browser for [server] and retries once it hands back a
  /// session.
  Future<void> _verify(
    BuildContext context,
    WidgetRef ref,
    Server server,
  ) async {
    final cleared = await context.router.push<bool>(
      WebChallengeRoute(serverId: server.id),
    );
    if (cleared != true || !context.mounted) return;
    unawaited(ref.read(pageStateProvider.notifier).load());
  }

  /// Drops the rating filter. The feed watches the rating as part of its
  /// result window and restarts the fetch itself, so the card only has to
  /// write the choice.
  Future<void> _disableRatingSafe(WidgetRef ref) async {
    await ref
        .read(serverSettingStateProvider.notifier)
        .setRating(BooruRating.all);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final server = ref.watch(serverStateProvider).getById(session.serverId);
    final safeRating = data.option.searchRating == BooruRating.safe;
    final challenged = isCloudflareChallenge(error);
    final needsAuth = isAuthRequired(error);
    // The page had entries; a local filter hid every one of them. Neither the
    // rating hint nor retrying can bring them back, so the card leads with the
    // filter that owns the answer.
    final filtered = error == BooruError.filtered;
    final blockedQuery = error == BooruError.tagsBlocked;
    final filterAnswer = filtered || blockedQuery;
    final filtering = ref.watch(
      contentSettingStateProvider.select(
        (it) => it.hideFavorited || it.hideDownloaded,
      ),
    );
    // The session server is gone: the card carries no error of its own, and
    // the only way out is a different server. Retrying or changing the rating
    // cannot make this one resolve.
    final missingServer = error == null;

    void showAll() {
      final settings = ref.read(contentSettingStateProvider.notifier);
      unawaited(settings.setHideFavorited(false));
      unawaited(settings.setHideDownloaded(false));
    }

    void manageBlocked() =>
        unawaited(context.router.push(const TagsBlockerRoute()));

    return Center(
      child: NoticeCard(
        icon: _getIconForError(error),
        margin: const EdgeInsets.all(DesignTokens.spacingMd),
        children: Column(
          children: [
            ErrorInfo(
              error: buildPageStatusError(context, data, error, server),
              stackTrace: stackTrace,
            ),
            if (error == BooruError.empty)
              Padding(
                padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
                child: Text(
                  data.option.searchRating == BooruRating.safe
                      ? context.t.pageStatusEmptyHintRating
                      : context.t.pageStatusEmptyHint,
                  style: AppTextRoles.of(context).rowSupporting,
                ),
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: DesignTokens.spacingSm,
              runSpacing: DesignTokens.spacingSm,
              children: [
                // One filled action: the fix the page is asking for. Every
                // other way out is a text button, so the notice never shows
                // two controls of the same weight.
                if (missingServer)
                  FilledButton(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    child: Text(context.t.pageStatus.changeServer),
                  )
                else if (needsAuth)
                  // Retrying cannot fill in the key, so the filled action goes
                  // where the credentials live.
                  FilledButton.icon(
                    onPressed: () =>
                        context.router.push(ServerEditorRoute(server: server)),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(context.t.servers.edit(name: server.name)),
                  )
                else if (challenged)
                  // The server never read the query: answering the check is
                  // the only fix, and the rating toggle in the row below is
                  // the fallback rather than the other way around.
                  FilledButton(
                    onPressed: () => _verify(context, ref, server),
                    child: Text(context.t.pageStatus.verify),
                  )
                else if (filtered && filtering)
                  // The content filters are the ones hiding this page; lifting
                  // them brings the posts back.
                  FilledButton(
                    onPressed: showAll,
                    child: Text(context.t.pageStatus.showAll),
                  )
                else if (filterAnswer)
                  // Either the content filters are off, so the blocker is the
                  // one hiding the page, or the query itself carries a blocked
                  // tag. Both are answered on the blocker screen.
                  FilledButton(
                    onPressed: manageBlocked,
                    child: Text(context.t.tagsBlocker.title),
                  )
                else if (safeRating)
                  FilledButton(
                    onPressed: () => _disableRatingSafe(ref),
                    child: Text(context.t.rating.disableRatingSafe),
                  )
                else
                  FilledButton(
                    onPressed: ref.read(pageStateProvider.notifier).load,
                    child: Text(context.t.retry),
                  ),
                if (needsAuth && server.apiKeyUrl.isNotEmpty)
                  // The page the site itself points at for the key this
                  // notice is asking for, one tap away from the failure.
                  TextButton(
                    onPressed: () => unawaited(
                      launchUrlString(
                        server.apiKeyUrl,
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    child: Text(context.t.servers.credentials.getKey),
                  ),
                if (!missingServer && challenged && safeRating)
                  // The filter did not cause the challenge; it stays available
                  // as the way out when the check itself cannot be answered.
                  TextButton(
                    onPressed: () => _disableRatingSafe(ref),
                    child: Text(context.t.rating.disableRatingSafe),
                  ),
                if (!missingServer && safeRating && !filterAnswer)
                  // A rating filter cannot explain a page already reported as
                  // hidden by the local filters, so the hint stays away.
                  TextButton(
                    onPressed: ref.read(pageStateProvider.notifier).load,
                    child: Text(context.t.retry),
                  ),
                if (!missingServer && filtered && filtering)
                  // The blockers hide a page just as well; with the content
                  // filters on, they are the second suspect.
                  TextButton(
                    onPressed: manageBlocked,
                    child: Text(context.t.tagsBlocker.title),
                  ),
                if (!missingServer)
                  TextButton(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    child: Text(context.t.pageStatus.changeServer),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
