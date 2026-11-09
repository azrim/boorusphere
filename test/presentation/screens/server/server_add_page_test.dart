import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/provider.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/screens/server/server_add_page.dart';
import 'package:boorusphere/presentation/screens/server/server_editor_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import '../../../utils/hive.dart';
import '../../state/app_version_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveTestContainer hiveContainer;

  setUpAll(() async {
    hiveContainer = HiveTestContainer();
    // `ServerAddPage` reads `uiSettingStateProvider`, which reads the
    // encrypted settings box.
    await UserSettingsRepo.prepare();
  });

  tearDownAll(() async {
    await hiveContainer.dispose();
  });

  Widget harness() {
    return ProviderScope(
      overrides: [envRepoProvider.overrideWithValue(FakeEnvRepo())],
      child: TranslationProvider(
        child: const MaterialApp(home: ServerAddPage()),
      ),
    );
  }

  testWidgets('defaults to Scan mode and hides the engine dropdown', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    // Scan is the default mode: the engine dropdown is gone and the scan
    // affordance is shown instead.
    expect(find.byType(DropdownButtonFormField<BooruEngine>), findsNothing);
    expect(find.text(t.servers.scanHint), findsOneWidget);
  });

  testWidgets('switching to Manual reveals the engine dropdown', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text(t.servers.mode.manual));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<BooruEngine>), findsOneWidget);
    expect(find.text(t.servers.scanHint), findsNothing);
  });

  group('a scan answer belongs to the inputs it was taken from', () {
    testWidgets('editing the host and the account mid-scan drops the answer', (
      tester,
    ) async {
      // The fields stay editable while the probes are out, and the old page
      // only checked that the widget was still alive before it published what
      // came back. That paired the host of one server with the account typed
      // for another, and the first request then carried that key to a host
      // that had never been given it.
      final pending = Completer<ResponseBody>();
      final recording = _ScanAdapter((request) {
        if (request.uri.path != '/posts.json') return _gone;
        if (!pending.isCompleted) return pending.future;
        return _json(_danbooruOnePost);
      });
      final capture = await _mountScanPage(tester, recording);

      await tester.enterText(_field(t.servers.credentials.login), 'account-a');
      await tester.enterText(_field(t.servers.credentials.apiKey), 'key-a');
      await tester.tap(_scanButton);
      await tester.pump(const Duration(milliseconds: 10));
      expect(recording.requests.any((it) => it.uri.host == 'a.test'), isTrue);

      await tester.enterText(_field(t.servers.homepage), 'https://b.test');
      await tester.enterText(_field(t.servers.credentials.login), 'account-b');
      await tester.enterText(_field(t.servers.credentials.apiKey), 'key-b');
      pending.complete(_json(_danbooruOnePost));
      await tester.pumpAndSettle();

      // Nothing was published, so nothing can be saved: the reader has to ask
      // again, and the second scan sees the form as it now stands.
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);
      expect(capture.submitted, isNull);
      // And the stale probes stayed what they were: one host, one pair.
      for (final request in recording.requests) {
        expect(request.uri.host, 'a.test');
        expect(
          request.headers['Authorization'],
          'Basic ${base64Encode(utf8.encode('account-a:key-a'))}',
          reason: '${request.uri} was asked with another account',
        );
      }

      await tester.tap(_scanButton);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);
      await tester.tap(_addButton);
      await tester.pumpAndSettle();

      expect(capture.submitted?.homepage, 'https://b.test');
      expect(capture.submitted?.login, 'account-b');
      expect(capture.submitted?.apiKey, 'key-b');
      final second = recording.requests
          .where((it) => it.uri.host == 'b.test')
          .toList();
      expect(second, isNotEmpty);
      for (final request in second) {
        expect(
          request.headers['Authorization'],
          'Basic ${base64Encode(utf8.encode('account-b:key-b'))}',
        );
      }
    });

    testWidgets('changing the custom api address asks for a new scan', (
      tester,
    ) async {
      // The address is where the engine was looked for, so a scan of one host
      // says nothing about another. Editing it used to leave the finished scan
      // in place: Add stayed enabled and saved the address the reader had
      // already replaced, exactly like the homepage edit beside it does not.
      final recording = _ScanAdapter(
        (request) =>
            request.uri.path == '/posts.json' ? _json(_danbooruOnePost) : _gone,
      );
      final capture = await _mountScanPage(tester, recording);

      await tester.tap(_scanButton);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);

      await tester.tap(find.text(t.servers.useCustomApi));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);

      await tester.enterText(_field(t.servers.apiAddr), 'https://api-b.test');
      await tester.pump();
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);

      await tester.tap(_scanButton);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);
      await tester.tap(_addButton);
      await tester.pumpAndSettle();

      // The engine was looked for at the address the reader typed, and the
      // homepage stays what it was.
      expect(capture.submitted?.apiAddress, 'https://api-b.test');
      expect(capture.submitted?.homepage, 'https://a.test');
      expect(
        recording.requests
            .lastWhere((it) => it.uri.path == '/posts.json')
            .uri
            .host,
        'api-b.test',
      );
    });

    testWidgets(
      'preserves canonical https redirect and strips trailing slash on scan',
      (tester) async {
        final recording = _ScanAdapter((request) {
          if (request.uri.path == '/posts.json') {
            return ResponseBody.fromString(
                _danbooruOnePost,
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
                isRedirect: true,
              )
              ..redirects = [
                RedirectRecord(
                  301,
                  'GET',
                  Uri.parse('https://a.test/posts.json'),
                ),
              ];
          }
          if (request.uri.path == '/posts/100') {
            return ResponseBody.fromString(
                '<html><head><title>Post #100</title></head></html>',
                200,
                headers: {
                  Headers.contentTypeHeader: ['text/html'],
                },
                isRedirect: true,
              )
              ..redirects = [
                RedirectRecord(
                  301,
                  'GET',
                  Uri.parse('https://a.test/posts/100'),
                ),
              ];
          }
          return _gone;
        });
        final capture = await _mountScanPage(tester, recording);
        await tester.enterText(_field(t.servers.homepage), 'http://a.test/');
        await tester.pump();

        await tester.tap(_scanButton);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);
        await tester.tap(_addButton);
        await tester.pumpAndSettle();

        expect(capture.submitted?.homepage, 'https://a.test');
        expect(capture.submitted?.apiAddress, 'https://a.test');
      },
    );
  });

  group('ServerEditorPage', () {
    testWidgets(
      'saves credentials on a preset without parser ids and keeps typed credentials across engine changes',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const rule34Preset = Server(
          id: 'Rule34',
          homepage: 'https://rule34.xxx/',
          apiAddr: 'https://api.rule34.xxx/',
          searchUrl:
              'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}&json=1',
          tagSuggestionUrl: 'autocomplete.php?q={tag-part}',
          postUrl: 'index.php?page=post&s=view&id={post-id}',
        );
        final capture = _CaptureServerState();
        final router = _MockStackRouter();
        when(router.maybePop).thenAnswer((_) async => true);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              envRepoProvider.overrideWithValue(FakeEnvRepo()),
              settingsRepoProvider.overrideWithValue(UserSettingsRepo(null)),
              booruParsersProvider.overrideWithValue([DanbooruJsonParser()]),
              serverStateProvider.overrideWith(() => capture),
            ],
            child: TranslationProvider(
              child: MaterialApp(
                home: StackRouterScope(
                  controller: router,
                  stateHash: 0,
                  child: const ServerEditorPage(server: rule34Preset),
                ),
              ),
            ),
          ),
        );

        await tester.enterText(_field(t.servers.credentials.login), 'alice');
        await tester.enterText(_field(t.servers.credentials.apiKey), 'key-123');
        await tester.pump();

        // Saving directly without picking an engine succeeds for auto-detected
        // presets and strips trailing slashes from the saved addresses.
        await tester.tap(find.widgetWithText(FilledButton, t.save));
        await tester.pumpAndSettle();

        expect(capture.edited?.login, 'alice');
        expect(capture.edited?.apiKey, 'key-123');
        expect(capture.edited?.homepage, 'https://rule34.xxx');
        expect(capture.edited?.apiAddr, 'https://api.rule34.xxx');

        // Picking an engine updates the query templates while keeping the
        // credentials already typed in the form.
        await tester.tap(find.byType(DropdownButtonFormField<BooruEngine>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Danbooru').last);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, t.save));
        await tester.pumpAndSettle();

        expect(capture.edited?.searchParserId, 'Danbooru.json');
        expect(capture.edited?.login, 'alice');
        expect(capture.edited?.apiKey, 'key-123');
      },
    );
  });
}

/// One Danbooru post, which is all the scan needs to recognise an engine.
const _danbooruOnePost =
    '[{"id":1,"file_url":"https://img.test/1.jpg",'
    '"preview_file_url":"https://img.test/1-preview.jpg",'
    '"tag_string":"cat","image_width":100,"image_height":100,"rating":"g"}]';

ResponseBody _json(String value) => ResponseBody.fromString(
  value,
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody get _gone => ResponseBody.fromBytes(
  [],
  404,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Finder get _scanButton => find.widgetWithText(FilledButton, t.scan);
Finder get _addButton => find.widgetWithText(FilledButton, t.servers.add);

/// Answers by rule and keeps every request, headers included.
class _ScanAdapter implements HttpClientAdapter {
  _ScanAdapter(this.answer);

  final FutureOr<ResponseBody> Function(RequestOptions) answer;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await answer(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Stops at the persistence boundary: these tests must not write a real box,
/// and what they claim about is the server handed to `add` or `edit`.
class _CaptureServerState extends ServerState {
  Server? submitted;
  Server? edited;

  @override
  Iterable<Server> build() => [];

  @override
  Future<void> add(Server value) async {
    submitted = value;
    throw ServerAlreadyExistsException(value);
  }

  @override
  Future<void> edit(Server old, Server updated) async {
    edited = updated;
  }
}

/// The page with one engine to find, a host that answers, and a name and
/// homepage already typed in.
Future<_CaptureServerState> _mountScanPage(
  WidgetTester tester,
  _ScanAdapter adapter,
) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final capture = _CaptureServerState();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        envRepoProvider.overrideWithValue(FakeEnvRepo()),
        settingsRepoProvider.overrideWithValue(UserSettingsRepo(null)),
        dioProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
        booruParsersProvider.overrideWithValue([DanbooruJsonParser()]),
        serverStateProvider.overrideWith(() => capture),
      ],
      child: TranslationProvider(
        child: const MaterialApp(home: ServerAddPage()),
      ),
    ),
  );
  await tester.enterText(_field(t.servers.profileName), 'Board A');
  await tester.enterText(_field(t.servers.homepage), 'https://a.test');
  await tester.pump();
  return capture;
}

class _MockStackRouter extends Mock implements StackRouter {}
