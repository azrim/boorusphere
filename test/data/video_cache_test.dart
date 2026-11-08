import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:boorusphere/data/repository/video_cache/video_cache.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Answers every request with the body [respond] builds and records the
/// options it was asked with.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

/// MP4 bytes: the `ftyp` box the media check expects at offset 4, padded to
/// [size] so an eviction test can reason about exact lengths.
Uint8List _mp4({int size = 1024}) {
  final bytes = Uint8List(size);
  bytes.setRange(0, 12, const [
    0x00,
    0x00,
    0x00,
    0x20,
    0x66,
    0x74,
    0x79,
    0x70,
    0x69,
    0x73,
    0x6F,
    0x6D,
  ]);
  return bytes;
}

ResponseBody _video(Uint8List bytes) {
  return ResponseBody.fromBytes(
    bytes,
    200,
    headers: {
      Headers.contentTypeHeader: ['video/mp4'],
      Headers.contentLengthHeader: ['${bytes.length}'],
    },
  );
}

Dio _dio(HttpClientAdapter adapter) {
  return Dio()..httpClientAdapter = adapter;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('video_cache_test_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  VideoCache buildCache(
    Dio dio, {
    int maxBytes = VideoCache.defaultMaxBytes,
    DateTime Function()? now,
  }) {
    return VideoCache(
      client: dio,
      directory: () async => dir,
      maxBytes: maxBytes,
      now: now,
    );
  }

  File cachedFile(String url) {
    return File(p.join(dir.path, '${VideoCache.keyFor(url)}.mp4'));
  }

  test('downloads the video once and serves it from disk afterwards', () async {
    final bytes = _mp4();
    final adapter = _FakeAdapter((_) => _video(bytes));
    final cache = buildCache(_dio(adapter));
    const url = 'https://cdn.test/file/1.mp4?token=abc';

    final file = await cache.cache(url, {'referer': 'https://booru.test/1'});

    expect(file, isNotNull);
    expect(file!.readAsBytesSync(), bytes);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.headers['referer'], 'https://booru.test/1');

    final again = await cache.cache(url, {});
    expect(again!.path, file.path);
    expect(adapter.requests, hasLength(1), reason: 'the second call is a hit');
  });

  test('a truncated file is dropped and reported as a miss', () async {
    const url = 'https://cdn.test/file/1.mp4';
    final adapter = _FakeAdapter((_) => _video(_mp4()));
    final cache = buildCache(_dio(adapter));

    final file = await cache.cache(url, {});
    expect(file, isNotNull);
    file!.writeAsBytesSync(const [1, 2, 3]);

    expect(await cache.lookup(url), isNull);
    expect(file.existsSync(), isFalse);
    expect((await cache.stats()).bytes, 0);
    expect((await cache.stats()).count, 0);
  });

  test('rejects the markup page a hotlink-protected server returns', () async {
    final adapter = _FakeAdapter(
      (_) => ResponseBody.fromString(
        '<html><body>hotlink denied</body></html>',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
          Headers.contentLengthHeader: ['40'],
        },
      ),
    );
    final cache = buildCache(_dio(adapter));

    final file = await cache.cache('https://cdn.test/file/1.mp4', {});

    expect(file, isNull);
    final names = dir
        .listSync()
        .whereType<File>()
        .map((it) => p.basename(it.path))
        .toList();
    expect(names, ['index.json']);
    expect((await cache.stats()).bytes, 0);
  });

  test('does not keep a response larger than the whole cache', () async {
    final adapter = _FakeAdapter((_) => _video(_mp4()));
    final cache = buildCache(_dio(adapter), maxBytes: 512);

    final file = await cache.cache('https://cdn.test/file/1.mp4', {});

    expect(file, isNull);
    expect((await cache.stats()).bytes, 0);
  });

  test(
    'evicts the least recently used video, not the one just replayed',
    () async {
      const a = 'https://cdn.test/file/a.mp4';
      const b = 'https://cdn.test/file/b.mp4';
      const c = 'https://cdn.test/file/c.mp4';
      var clock = DateTime(2026);

      final adapter = _FakeAdapter((options) => _video(_mp4()));
      final cache = buildCache(_dio(adapter), maxBytes: 2500, now: () => clock);

      await cache.cache(a, {});
      clock = clock.add(const Duration(minutes: 1));
      await cache.cache(b, {});
      clock = clock.add(const Duration(minutes: 1));
      expect(await cache.lookup(a), isNotNull, reason: 'a is replayed now');
      clock = clock.add(const Duration(minutes: 1));
      await cache.cache(c, {});

      expect(await cache.lookup(a), isNotNull);
      expect(await cache.lookup(b), isNull);
      expect(await cache.lookup(c), isNotNull);
      expect(cachedFile(b).existsSync(), isFalse);
      expect(adapter.requests, hasLength(3), reason: 'the replay stays local');
    },
  );

  test(
    'lowering the limit evicts the least recently used right away',
    () async {
      const a = 'https://cdn.test/file/a.mp4';
      const b = 'https://cdn.test/file/b.mp4';
      var clock = DateTime(2026);

      final adapter = _FakeAdapter((options) => _video(_mp4()));
      final cache = buildCache(_dio(adapter), maxBytes: 2500, now: () => clock);

      await cache.cache(a, {});
      clock = clock.add(const Duration(minutes: 1));
      await cache.cache(b, {});
      expect((await cache.stats()).count, 2);

      await cache.applyMaxBytes(1024);

      expect(cache.maxBytes, 1024);
      final stats = await cache.stats();
      expect(stats.bytes, 1024);
      expect(stats.count, 1);
      expect(await cache.lookup(a), isNull);
      expect(await cache.lookup(b), isNotNull);
      expect(cachedFile(a).existsSync(), isFalse);
    },
  );

  test('a second instance reads the index of the first', () async {
    const url = 'https://cdn.test/file/1.mp4';
    final first = buildCache(_dio(_FakeAdapter((_) => _video(_mp4()))));
    final file = await first.cache(url, {});
    expect(file, isNotNull);

    final offline = _FakeAdapter(
      (_) => throw StateError('the cache should not reach the network'),
    );
    final second = buildCache(_dio(offline));

    final reopened = await second.lookup(url);

    expect(reopened, isNotNull);
    expect(reopened!.path, file!.path);
    expect(offline.requests, isEmpty);
  });

  test('clear removes every stored video and the recorded size', () async {
    const first = 'https://cdn.test/file/a.mp4';
    const second = 'https://cdn.test/file/b.mp4';
    final adapter = _FakeAdapter((_) => _video(_mp4()));
    final cache = buildCache(_dio(adapter));

    await cache.cache(first, {});
    await cache.cache(second, {});
    final stored = await cache.stats();
    expect(stored.bytes, 2048);
    expect(stored.count, 2);

    await cache.clear();

    expect((await cache.stats()).bytes, 0);
    expect((await cache.stats()).count, 0);
    expect(cachedFile(first).existsSync(), isFalse);
    expect(cachedFile(second).existsSync(), isFalse);
  });

  test('rejects a body that stops before its declared length', () async {
    final bytes = _mp4();
    final adapter = _FakeAdapter(
      // The head alone would pass as media; the length it was promised is
      // what marks the transfer as short.
      (_) => ResponseBody(
        Stream.value(Uint8List.sublistView(bytes, 0, 12)),
        200,
        headers: {
          Headers.contentTypeHeader: ['video/mp4'],
          Headers.contentLengthHeader: ['${bytes.length}'],
        },
      ),
    );
    final cache = buildCache(_dio(adapter));

    final file = await cache.cache('https://cdn.test/file/1.mp4', {});

    expect(file, isNull);
    expect((await cache.stats()).count, 0);
    expect(dir.listSync().whereType<File>().map((it) => p.basename(it.path)), [
      'index.json',
    ]);
  });

  test(
    'remove drops the stored copy so the next call downloads again',
    () async {
      const url = 'https://cdn.test/file/1.mp4';
      final adapter = _FakeAdapter((_) => _video(_mp4()));
      final cache = buildCache(_dio(adapter));

      final file = await cache.cache(url, {});
      expect(file, isNotNull);

      await cache.remove(url);

      expect(file!.existsSync(), isFalse);
      expect(await cache.lookup(url), isNull);
      expect((await cache.stats()).count, 0);

      final again = await cache.cache(url, {});
      expect(again, isNotNull);
      expect(adapter.requests, hasLength(2));
    },
  );

  test('cancel stops a transfer that has not finished', () async {
    const url = 'https://cdn.test/file/1.mp4';
    final body = StreamController<Uint8List>();
    final requestStarted = Completer<void>();
    final adapter = _FakeAdapter((_) {
      requestStarted.complete();
      return ResponseBody(
        body.stream,
        200,
        headers: {
          Headers.contentTypeHeader: ['video/mp4'],
          Headers.contentLengthHeader: ['1024'],
        },
      );
    });
    final cache = buildCache(_dio(adapter));

    final pending = cache.cache(url, {});
    await requestStarted.future;
    body.add(Uint8List.sublistView(_mp4(), 0, 512));
    await Future<void>.delayed(Duration.zero);

    cache.cancel(url);
    body.add(Uint8List.sublistView(_mp4(), 512, 1024));
    await body.close();

    expect(await pending, isNull);
    expect(dir.listSync().whereType<File>().map((it) => p.basename(it.path)), [
      'index.json',
    ]);
    expect((await cache.stats()).count, 0);
  });

  test('clear stops a transfer that is still running', () async {
    const url = 'https://cdn.test/file/1.mp4';
    final body = StreamController<Uint8List>();
    final requestStarted = Completer<void>();
    final adapter = _FakeAdapter((_) {
      requestStarted.complete();
      return ResponseBody(
        body.stream,
        200,
        headers: {
          Headers.contentTypeHeader: ['video/mp4'],
          Headers.contentLengthHeader: ['1024'],
        },
      );
    });
    final cache = buildCache(_dio(adapter));

    final pending = cache.cache(url, {});
    await requestStarted.future;
    body.add(Uint8List.sublistView(_mp4(), 0, 512));
    await Future<void>.delayed(Duration.zero);

    await cache.clear();
    body.add(Uint8List.sublistView(_mp4(), 512, 1024));
    await body.close();

    expect(await pending, isNull);
    expect(dir.listSync().whereType<File>(), isEmpty);
    expect((await cache.stats()).count, 0);
  });

  test('a ghost row in the index cannot evict the live videos', () async {
    const a = 'https://cdn.test/file/a.mp4';
    const b = 'https://cdn.test/file/b.mp4';
    var clock = DateTime(2026);
    final adapter = _FakeAdapter((_) => _video(_mp4()));
    final first = buildCache(_dio(adapter), maxBytes: 2500, now: () => clock);

    await first.cache(a, {});
    clock = clock.add(const Duration(minutes: 1));
    await first.cache(b, {});

    // A crash can leave a row whose file never landed. It must not weigh on
    // the budget when the index is read back, or it pushes a live video out.
    final index = File(p.join(dir.path, 'index.json'));
    final raw = jsonDecode(index.readAsStringSync()) as Map<String, dynamic>;
    final entries = raw['entries'] as Map<String, dynamic>;
    entries['deadbeef'] = {
      'url': 'https://cdn.test/file/gone.mp4',
      'file': 'deadbeef.mp4',
      'size': 5000,
      'used': clock.millisecondsSinceEpoch,
    };
    index.writeAsStringSync(jsonEncode(raw));

    final second = buildCache(_dio(adapter), maxBytes: 2500, now: () => clock);
    final stats = await second.stats();

    expect(stats.count, 2);
    expect(stats.bytes, 2048);
    expect(await second.lookup(a), isNotNull);
    expect(await second.lookup(b), isNotNull);
    expect(cachedFile(a).existsSync(), isTrue);
    expect(cachedFile(b).existsSync(), isTrue);
  });

  test('stats drops a short file and deletes it', () async {
    const url = 'https://cdn.test/file/1.mp4';
    final adapter = _FakeAdapter((_) => _video(_mp4()));
    final cache = buildCache(_dio(adapter));

    final file = await cache.cache(url, {});
    expect(file, isNotNull);
    file!.writeAsBytesSync(const [1, 2, 3]);

    final stats = await cache.stats();

    expect(stats.bytes, 0);
    expect(stats.count, 0);
    expect(file.existsSync(), isFalse);
  });
}
