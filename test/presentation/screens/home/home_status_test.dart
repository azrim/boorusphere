import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/entity/page_data.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/entity/content_setting.dart';
import 'package:boorusphere/presentation/screens/home/home_status.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _server = Server(id: 'Safebooru', homepage: 'https://safebooru.org');

class _StubServerState extends ServerState {
  @override
  Iterable<Server> build() => const [_server];
}

class _StubPageState extends PageState {
  _StubPageState(this.result);

  final FetchResult<PageData> result;

  @override
  FetchResult<PageData> build() => result;
}

/// The status card reads the content filters to know whether they are the ones
/// hiding the page; the real notifier would read storage.
class _StubContentSettings extends ContentSettingState {
  _StubContentSettings({this.filtering = false});

  final bool filtering;

  @override
  ContentSetting build() =>
      ContentSetting(hideFavorited: filtering, hideDownloaded: false);
}

void main() {
  Widget harness(
    Object error, {
    BooruRating rating = BooruRating.safe,
    bool filtering = false,
  }) {
    final result = FetchResult<PageData>.error(
      PageData(option: PageOption(searchRating: rating)),
      error: error,
    );
    return ProviderScope(
      overrides: [
        searchSessionProvider.overrideWith(
          (ref) => const SearchSession(serverId: 'Safebooru'),
        ),
        serverStateProvider.overrideWith(_StubServerState.new),
        contentSettingStateProvider.overrideWith(
          () => _StubContentSettings(filtering: filtering),
        ),
        pageStateProvider.overrideWith(() => _StubPageState(result)),
      ],
      child: TranslationProvider(
        child: const MaterialApp(home: Scaffold(body: HomeStatus())),
      ),
    );
  }

  testWidgets('a challenge offers Verify before the rating toggle', (
    tester,
  ) async {
    await tester.pumpWidget(harness(BooruError.cloudflareChallenge));
    await tester.pump();

    expect(
      find.widgetWithText(FilledButton, t.pageStatus.verify),
      findsOneWidget,
      reason:
          'the server never read the query, so answering the check is the '
          'action that can resolve the page',
    );
    expect(
      find.widgetWithText(FilledButton, t.rating.disableRatingSafe),
      findsNothing,
      reason: 'the filter did not cause the challenge',
    );
    expect(
      find.widgetWithText(TextButton, t.rating.disableRatingSafe),
      findsOneWidget,
      reason: 'the toggle stays reachable as the fallback, one weight lower',
    );
  });

  testWidgets('a plain failure with rating:safe still leads with the toggle', (
    tester,
  ) async {
    await tester.pumpWidget(harness(BooruError.empty));
    await tester.pump();

    expect(
      find.widgetWithText(FilledButton, t.rating.disableRatingSafe),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, t.pageStatus.verify),
      findsNothing,
    );
  });

  testWidgets('a filtered page leads with the filter that hid it', (
    tester,
  ) async {
    // The content filters are off, so the blocker hid the page. The rating
    // filter cannot explain it and retrying would ask for the same page back.
    await tester.pumpWidget(harness(BooruError.filtered));
    await tester.pump();

    expect(
      find.widgetWithText(FilledButton, t.tagsBlocker.title),
      findsOneWidget,
      reason: 'the blocker screen is where the page can be brought back',
    );
    expect(
      find.widgetWithText(FilledButton, t.rating.disableRatingSafe),
      findsNothing,
    );
    expect(find.widgetWithText(TextButton, t.retry), findsNothing);
  });

  testWidgets('a filtered page with content filters on offers Show all', (
    tester,
  ) async {
    await tester.pumpWidget(harness(BooruError.filtered, filtering: true));
    await tester.pump();

    expect(
      find.widgetWithText(FilledButton, t.pageStatus.showAll),
      findsOneWidget,
      reason: 'the content filters own the page here',
    );
    expect(
      find.widgetWithText(TextButton, t.tagsBlocker.title),
      findsOneWidget,
      reason: 'the blockers stay one tap away as the second suspect',
    );
  });
}
