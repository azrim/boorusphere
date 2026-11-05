import 'dart:async';
import 'dart:convert';

import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_auth.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:logging/logging.dart';

BooruScanner useBooruScanner(
  Dio client,
  List<BooruParser> parsers, [
  List<Object?> keys = const [],
]) {
  final scanner = useMemoized(() {
    return BooruScanner(parsers: parsers, client: client);
  }, [client, parsers, ...keys]);

  useEffect(() {
    return scanner.stop;
  }, keys);

  return scanner;
}

enum _ScanType { search, suggestion, post }

class _ScanResult {
  const _ScanResult({
    this.origin = '',
    this.parserId = '',
    this.authBuilderId,
    this.query = '',
  });

  final String origin;
  final String parserId;
  final String query;
  final String? authBuilderId;

  static const empty = _ScanResult();
}

class BooruScanner {
  BooruScanner({required this.parsers, required this.client});

  final List<BooruParser> parsers;
  final Dio client;
  final _log = Logger('BooruScanner');

  late CancelToken _cancelToken = CancelToken();

  final _uiLogs = ValueNotifier(<String>[]);
  final _isScanning = ValueNotifier(false);

  ValueListenable<List<String>> get logs => _uiLogs;
  ValueListenable<bool> get isScanning => _isScanning;

  _uilog([String msg = '']) {
    _uiLogs.value = [..._uiLogs.value, msg];
  }

  _clearUiLog() {
    _uiLogs.value = [];
  }

  /// A probe is a yes/no question, so it must answer quickly: the shared
  /// client's retry policy would turn one slow parser into minutes of
  /// scanning, and the server list waits on every parser at once.
  static const _probeTimeout = Duration(seconds: 8);

  /// How much of a post page is worth reading to judge it. Every board the
  /// scanner is asked about writes its title within the first five hundred
  /// bytes, so the rest of the document is markup the verdict will not use —
  /// and a post page is routinely a few hundred kilobytes.
  static const _postHeadLimit = 8 * 1024;

  Future<String> _readHead(ResponseBody body) async {
    final bytes = <int>[];
    try {
      // Breaking out of an `await for` unsubscribes, which is also how the
      // connection is handed back: a probe that read the whole page would hold
      // the socket open for the rest of the scan and buy certainty nobody asked
      // for.
      await for (final chunk in body.stream) {
        bytes.addAll(chunk);
        if (bytes.length >= _postHeadLimit) break;
      }
    } catch (e) {
      // A body that ends early still says something: whatever arrived before it
      // stopped is what the engine gets to judge.
      _log.v('Post probe body ended early: $e');
    }

    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<_ScanResult> _scan(
    Server server, {
    required String host,
    required BooruParser parser,
    required _ScanType type,
  }) async {
    final loadQuery = switch (type) {
      _ScanType.post => parser.postUrl,
      _ScanType.search => parser.searchQuery,
      _ScanType.suggestion => parser.suggestionQuery,
    };

    if (loadQuery.isEmpty || _cancelToken.isCancelled) {
      return _ScanResult.empty;
    }

    final test = loadQuery
        .replaceAll('{tags}', '*')
        .replaceAll('{tag-part}', 'a')
        // sometimes realbooru won't show anything when limit is too low
        .replaceAll('{post-limit}', '30')
        // The probe has to ask for the page the reader will ask for first.
        // `{page-id}` and `{post-offset}` are counted from zero the way
        // `Server.searchUrlOf` fills them, so probing the second window would
        // judge an engine by a page nobody requests: a board with less than a
        // page of matches answers it without any entry at all, and the scan
        // then reports the host as having no engine even though its first page
        // parses fine. `{page-num}` is the ordinal the query-string engines
        // number from one, so it stays the first page.
        .replaceAll('{page-id}', '0')
        .replaceAll('{page-num}', '1')
        .replaceAll('{post-offset}', '0')
        .replaceAll('{post-id}', '100');
    try {
      final testUrl = '$host/$test';
      _uilog('→ checking ${type.name}::${parser.id}...');
      // Logged without credentials.
      _log.v('Scanning $testUrl');
      final options = Options(
        connectTimeout: _probeTimeout,
        sendTimeout: _probeTimeout,
        receiveTimeout: _probeTimeout,
        validateStatus: (it) => it == 200,
        headers: BooruAuth.headers(parser, server),
        responseType: type == _ScanType.post ? ResponseType.stream : null,
      );
      options.disableRetry = true;

      // Credentials ride along with the probe: a booru that gates its API
      // answers nothing without them, so a scan would report "no engine" for
      // a server the user can browse once the key is attached. They go in the
      // form that engine reads, which for a header engine means the URL the
      // probe is logged and sent as stays what it was.
      final probeUrl = BooruAuth.travelsInQuery(parser, server)
          ? server.appendCredentials(testUrl)
          : testUrl;
      final res = await client.get(
        probeUrl,
        options: options,
        cancelToken: _cancelToken,
      );

      final origin = res.redirects.isNotEmpty && res.realUri.hasAuthority
          ? res.realUri.origin
          : host;
      final body = res.data;

      if (type == _ScanType.post) {
        // A status code is not a page. The boards that gate access hand out
        // 200 for every path, so the answer has to be read before it counts:
        // whatever the engine calls a post page, and nothing else.
        final head = body is ResponseBody ? await _readHead(body) : '$body';
        if (!parser.isPostPage(head)) {
          _log.v('Post probe of $probeUrl refused: not a post page');
          return _ScanResult.empty;
        }

        return _ScanResult(
          origin: origin,
          parserId: parser.id,
          query: parser.postUrl,
        );
      }

      if (type == _ScanType.search) {
        if (parser.canParsePage(res)) {
          return _ScanResult(
            origin: origin,
            parserId: parser.id,
            query: parser.searchQuery,
            authBuilderId: parser.id,
          );
        }

        final realParser = parsers.firstWhere(
          (x) => x.canParsePage(res),
          orElse: NoParser.new,
        );
        return _ScanResult(
          origin: origin,
          parserId: realParser.id,
          query: parser.searchQuery,
          authBuilderId: parser.id,
        );
      }

      if (type == _ScanType.suggestion) {
        if (parser.canParseSuggestion(res)) {
          return _ScanResult(
            origin: origin,
            parserId: parser.id,
            query: parser.suggestionQuery,
          );
        }

        final realParser = parsers.firstWhere(
          (x) => x.canParseSuggestion(res),
          orElse: NoParser.new,
        );
        return _ScanResult(
          origin: origin,
          parserId: realParser.id,
          query: parser.suggestionQuery,
        );
      }

      return _ScanResult.empty;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        rethrow;
      }

      return _ScanResult.empty;
    }
  }

  Stream<_ScanResult> _performScans(
    String host, {
    required Server server,
    required _ScanType type,
    String preferEngine = '',
  }) async* {
    /// Where a candidate belongs in the ordering [results] are picked from.
    ///
    /// The post pass asks every engine's page route against one host, and a
    /// page only has to carry a title and not be a known gate to count as an
    /// answer — which a soft 404, a catch-all app, or a login redirect passes
    /// on a route that is not this board's post page at all. Ranking by the
    /// parser id suffix alone let that stranger win and wrote a post address
    /// the host does not serve. The engine the search pass proved does know
    /// where its own posts live, so its template comes first; a foreign route
    /// is still allowed to answer when the proven engine has no page template
    /// of its own, which is how a Danbooru-shaped board read by another
    /// parser's JSON keeps a working link. The id suffix breaks ties, so the
    /// scan decides the same way every time it runs.
    int engineRank(String parserId) {
      if (preferEngine.isEmpty) return 0;
      return parserId.fileNameNoExt == preferEngine ? 0 : 1;
    }

    final results = <_ScanResult>[];
    final requests = parsers.mapIndexed((i, parser) async {
      if (i > 0) {
        await Future.delayed(Duration(milliseconds: i * 100));
      }
      return _scan(server, host: host, parser: parser, type: type);
    });

    await for (final result in Future.wait(requests).asStream()) {
      for (final scanResult in result) {
        if (scanResult != _ScanResult.empty) {
          results.add(scanResult);
        }

        yield _ScanResult.empty;
      }
    }

    results.sort((a, b) {
      final byEngine = engineRank(a.parserId).compareTo(engineRank(b.parserId));
      return byEngine != 0
          ? byEngine
          : a.parserId.fileExt.compareTo(b.parserId.fileExt);
    });
    final firstFound = results.firstWhere(
      (it) => it.query.isNotEmpty && it.parserId.isNotEmpty,
      orElse: () =>
          _ScanResult(origin: host, authBuilderId: '', parserId: '', query: ''),
    );

    if (firstFound.parserId.isEmpty) {
      _uilog('no ${type.name}Query matched');
    } else {
      _uilog('${type.name}Query matched: ${firstFound.parserId}');
    }

    _uilog();
    yield firstFound;
  }

  Future<Server> scan(Server server) async {
    final api = server.apiAddress.replaceFirst(RegExp(r'/$'), '');
    final home = server.homepage.replaceFirst(RegExp(r'/$'), '');
    var data = server;

    _isScanning.value = true;
    _clearUiLog();

    try {
      _uilog('Scanning search query...');
      _cancelToken = CancelToken();
      final search = _performScans(api, server: data, type: _ScanType.search);
      await for (var ev in search) {
        if (ev == _ScanResult.empty && isScanning.value) {
          continue;
        }

        data = data.copyWith(
          searchParserId: ev.parserId,
          searchUrl: ev.query,
          apiAddr: ev.origin,
        );
      }

      _uilog('Scanning suggestion query...');
      final suggestion = _performScans(
        api,
        server: data,
        type: _ScanType.suggestion,
      );
      await for (var ev in suggestion) {
        if (ev == _ScanResult.empty && isScanning.value) {
          continue;
        }

        // The suggestion pass is asked against the address the search pass
        // proved, so all it gets to decide is which parser reads the
        // completion answer. Its origin is written nowhere: `apiAddr` serves
        // search as well, so a tag endpoint that redirects out of the api host
        // would move every post request to a server that never proved it
        // answers them. A route that only exists on such a foreign host is not
        // representable in this model at all, so it is dropped instead of half
        // configured — suggestions stay off while the search that works stays.
        if (ev.parserId.isEmpty) continue;
        if (ev.origin != data.apiAddr) {
          _uilog('suggestion host ${ev.origin} differs from the api address');
          continue;
        }

        data = data.copyWith(
          suggestionParserId: ev.parserId,
          tagSuggestionUrl: ev.query,
        );
      }

      _uilog('Scanning web post query...');
      final post = _performScans(
        home,
        server: data,
        type: _ScanType.post,
        preferEngine: data.searchParserId.fileNameNoExt,
      );
      await for (var ev in post) {
        if (ev == _ScanResult.empty && isScanning.value) {
          continue;
        }

        // The post pass writes two things the user typed, so an answer that
        // found nothing must not write them at all: an empty post page makes
        // every post link resolve to the site root without an error anywhere,
        // and the probe host is not the homepage of a site that redirected.
        if (ev.parserId.isEmpty) {
          continue;
        }

        data = data.copyWith(postUrl: ev.query, homepage: ev.origin);
      }

      // The probe is Scan mode's only way to learn the post address, and a
      // gated board can refuse it — but the dialect the search pass settled on
      // already knows where that engine's posts live, which is a better answer
      // than a link to the homepage. Manual adds carry the address anyway, and
      // a scan that found no engine at all has nothing to borrow it from.
      if (data.postUrl.isEmpty) {
        final dialect = parsers.firstWhereOrNull(
          (it) => it.id == data.searchParserId && it.postUrl.isNotEmpty,
        );
        if (dialect != null) {
          data = data.copyWith(postUrl: dialect.postUrl);
          _uilog('post page taken from ${dialect.id}');
        }
      }

      _isScanning.value = false;
      return data.copyWith(
        apiAddr: data.apiAddr == data.homepage ? '' : data.apiAddr,
        id: data.id.isEmpty ? home.toUri().host : data.id,
      );
    } catch (e) {
      _isScanning.value = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    _isScanning.value = false;
    _cancelToken.cancel();
  }
}
