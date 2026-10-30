import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/entity/page_data.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
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
import 'package:boorusphere/utils/http/cloudflare.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomeStatus extends HookConsumerWidget {
  const HomeStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(pageStateProvider);

    return switch (pageState) {
      IdleFetchResult() || DataFetchResult() => const SizedBox.shrink(),
      LoadingFetchResult() => const TimelineSkeleton(),
      ErrorFetchResult(:final data, :final error, :final stackTrace) =>
        _ErrorStatus(data: data, error: error, stackTrace: stackTrace),
    };
  }
}

class _ErrorStatus extends ConsumerWidget {
  const _ErrorStatus({required this.data, this.error, this.stackTrace});

  final PageData data;
  final Object? error;
  final StackTrace? stackTrace;

  Object? buildError(BuildContext context, Server server) {
    final e = error;
    if (isCloudflareChallenge(e)) {
      // Not a rejection of the query: the server never read it. The status
      // code would read as the server's answer, so the line says what the
      // check is and the card offers the browser that can answer it.
      return context.t.pageStatus.cloudflareChallenge(serverName: server.name);
    } else if (e is DioException && e.response?.statusCode != null) {
      return context.t.pageStatus
          .httpError(serverName: server.name)
          .withDioExceptionCode(e);
    } else if (e == BooruError.empty) {
      return data.option.query.isEmpty
          ? context.t.pageStatus.noResult(n: data.posts.length)
          : context.t.pageStatus.noResultForQuery(
              n: data.posts.length,
              query: data.option.query,
            );
    } else if (e == BooruError.tagsBlocked) {
      return context.t.pageStatus.blocked(query: data.option.query);
    } else if (e == BooruError.unparsable) {
      return context.t.pageStatus.unparsable(serverName: server.name);
    } else {
      return e;
    }
  }

  Icon _getIconForError(Object? error) {
    if (isCloudflareChallenge(error)) {
      return const Icon(Icons.shield_outlined);
    } else if (error is DioException) {
      return const Icon(Icons.wifi_off);
    } else if (error == BooruError.empty) {
      return const Icon(Icons.explore_off);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final server = ref.watch(serverStateProvider).getById(session.serverId);
    final safeRating = data.option.searchRating == BooruRating.safe;
    final challenged = isCloudflareChallenge(error);

    return Center(
      child: NoticeCard(
        icon: _getIconForError(error),
        margin: const EdgeInsets.all(DesignTokens.spacingMd),
        children: Column(
          children: [
            ErrorInfo(
              error: buildError(context, server),
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
                if (safeRating)
                  FilledButton(
                    onPressed: () async {
                      await ref
                          .read(serverSettingStateProvider.notifier)
                          .setRating(BooruRating.all);
                      if (context.mounted) {
                        unawaited(ref.read(pageStateProvider.notifier).load());
                      }
                    },
                    child: Text(context.t.rating.disableRatingSafe),
                  )
                else if (challenged)
                  FilledButton(
                    onPressed: () => _verify(context, ref, server),
                    child: Text(context.t.pageStatus.verify),
                  )
                else
                  FilledButton(
                    onPressed: ref.read(pageStateProvider.notifier).load,
                    child: Text(context.t.retry),
                  ),
                if (safeRating)
                  TextButton(
                    onPressed: ref.read(pageStateProvider.notifier).load,
                    child: Text(context.t.retry),
                  ),
                if (safeRating && challenged)
                  TextButton(
                    onPressed: () => _verify(context, ref, server),
                    child: Text(context.t.pageStatus.verify),
                  ),
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
