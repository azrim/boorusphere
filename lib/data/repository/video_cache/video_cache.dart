import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/utils/logger.dart';
import 'package:boorusphere/utils/media_file.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

/// Disk cache for videos the viewer streamed.
///
/// The first watch streams from the server while the same bytes are written
/// here in the background; the next watch is served from the local file. The
/// index is a small JSON document next to the files, so the least recently
/// used entry can be evicted once [maxBytes] is exceeded.
///
/// Files are named after a hash of their URL: a URL can carry a signed query
/// and must not show up in a file name. The index keeps the URL beside the
/// name, so a hash collision can never serve another video.
class VideoCache {
  VideoCache({
    required Dio client,
    required Future<Directory> Function() directory,
    DateTime Function()? now,
    int maxBytes = defaultMaxBytes,
    this.maxConcurrentDownloads = 2,
  }) : _client = client, // ignore: prefer_initializing_formals
       _directory = directory, // ignore: prefer_initializing_formals
       _now = now ?? DateTime.now,
       // A private field cannot be a named initializing formal, and the
       // constructor exposes the budget under its public name.
       _maxBytes = maxBytes; // ignore: prefer_initializing_formals

  /// Three hundred megabytes: a few short clips and the last long one, with
  /// enough headroom that the next watch still hits. Kept below the usual
  /// half-gigabyte phone cache budget so the system does not clear it first.
  static const defaultMaxBytes = 300 * 1024 * 1024;

  /// Bounds for a budget chosen in the settings. A cache constructed directly
  /// (tests, tools) may use any budget; the stored setting is the one that has
  /// to stay within a range a phone can actually hold.
  static const minBudgetBytes = 100 * 1024 * 1024;
  static const maxBudgetBytes = 1024 * 1024 * 1024;

  static const _indexName = 'index.json';
  static const _indexVersion = 1;

  /// Downloads beyond this are skipped rather than queued: a reader swiping
  /// through clips must not have every one of them pulled down at once.
  final int maxConcurrentDownloads;

  final Dio _client;
  final Future<Directory> Function() _directory;
  final DateTime Function() _now;

  int _maxBytes;
  final _entries = <String, _CacheEntry>{};
  final _inflight = <String, Future<File?>>{};

  Directory? _dir;
  bool _loaded = false;

  /// Serializes index reads and writes: two evictions or a touch and a store
  /// landing at once would otherwise write a stale entry map back.
  Future<void> _serial = Future.value();

  /// Bytes the cache may hold before the least recently watched entry is
  /// dropped.
  int get maxBytes => _maxBytes;

  /// Applies a new budget and drops the oldest videos right away, so lowering
  /// the limit does not leave the cache over it until the next download.
  Future<void> applyMaxBytes(int bytes) {
    return _exclusive(() async {
      _maxBytes = bytes;
      await _ensureLoaded();
      await _evictToFit();
      await _writeIndex();
    });
  }

  /// Key of [url] as it appears on disk. Two independent 64-bit FNV-1a passes
  /// make a collision a practical impossibility without pulling in a hashing
  /// package; the URL in the index is still checked on every lookup.
  static String keyFor(String url) {
    var first = 0xcbf29ce484222325;
    var second = 0x84222325cbf29ce4;
    for (final byte in utf8.encode(url)) {
      first = (first ^ byte) * 0x100000001b3;
      second = (second ^ byte) * 0x100000001b3;
    }
    return first.toUnsigned(64).toRadixString(16).padLeft(16, '0') +
        second.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  /// The cached file for [url], or null when it has not been cached yet.
  ///
  /// A hit counts as a use, so the next eviction takes the entry that has
  /// gone unopened the longest instead of one that is being replayed.
  Future<File?> lookup(String url) {
    final key = keyFor(url);
    return _exclusive(() async {
      await _ensureLoaded();
      final entry = _entries[key];
      if (entry == null || entry.url != url) return null;

      final dir = await _ensureDir();
      final file = File(p.join(dir.path, entry.file));
      if (!file.existsSync() || file.lengthSync() != entry.size) {
        _entries.remove(key);
        if (file.existsSync()) {
          try {
            await file.delete();
          } catch (e) {
            mainLog.w('VideoCache: failed to drop ${file.path}', e);
          }
        }
        await _writeIndex();
        return null;
      }

      entry.used = _now().millisecondsSinceEpoch;
      await _writeIndex();
      return file;
    });
  }

  /// Returns the cached file for [url], downloading it first when missing.
  ///
  /// Null means the video was not cached: the response was not media, the
  /// transfer failed, or another download already fills the concurrency
  /// budget. A null never reaches the player; playback falls back to the
  /// network stream.
  Future<File?> cache(String url, Map<String, String> headers) async {
    File? hit;
    try {
      hit = await lookup(url);
    } catch (e) {
      // An unreadable cache is no reason to skip the download: this call is
      // the one that may be able to rewrite it.
      mainLog.w('VideoCache: failed to read the cache for $url', e);
    }
    if (hit != null) return hit;

    final key = keyFor(url);
    final pending = _inflight[key];
    if (pending != null) return pending;
    if (_inflight.length >= maxConcurrentDownloads) return null;

    final future = _download(key, url, headers);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(key)?.ignore();
    }
  }

  /// Removes every cached video, keeping the directory for the next one.
  Future<void> clear() {
    return _exclusive(() async {
      await _ensureLoaded();
      final dir = await _ensureDir();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        try {
          await entity.delete();
        } catch (e) {
          mainLog.w('VideoCache: failed to clear ${entity.path}', e);
        }
      }
      _entries.clear();
      _loaded = false;
      _dir = null;
    });
  }

  /// What the cache currently holds.
  ///
  /// Entries whose file is gone or shortened are dropped first, so the answer
  /// only counts videos that can actually be replayed.
  Future<VideoCacheStats> stats() {
    return _exclusive(() async {
      await _ensureLoaded();
      final dir = await _ensureDir();
      var changed = false;
      _entries.removeWhere((_, entry) {
        final file = File(p.join(dir.path, entry.file));
        final intact = file.existsSync() && file.lengthSync() == entry.size;
        if (!intact) changed = true;
        return !intact;
      });
      if (changed) await _writeIndex();
      return VideoCacheStats(
        bytes: _entries.values.fold<int>(0, (sum, entry) => sum + entry.size),
        count: _entries.length,
      );
    });
  }

  Future<File?> _download(
    String key,
    String url,
    Map<String, String> headers,
  ) async {
    File? temp;
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        return null;
      }

      // A cache without a writable folder cannot keep anything, so the
      // request is not worth making.
      final dir = await _ensureDir();

      final res = await _client.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          followRedirects: true,
          validateStatus: (status) => status == 200,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final body = res.data;
      if (body == null) return null;

      final contentType = res.headers.value(Headers.contentTypeHeader);
      // The page a hotlink-protected booru returns instead of the file is
      // large enough to look like a video by size alone; the header and the
      // head bytes are what rule it out.
      if (_isMarkupContentType(contentType)) return null;
      final declared = body.contentLength;
      if (declared > maxBytes) return null;

      final extension = _extensionFor(uri, contentType);
      temp = File(p.join(dir.path, '$key.part$extension'));
      if (temp.existsSync()) await temp.delete();

      final sink = temp.openWrite();
      var received = 0;
      try {
        await for (final chunk in body.stream) {
          received += chunk.length;
          // An answer without a length can only be stopped once it is over
          // the cap; keeping the partial file would fill the cache with a
          // video that could never be served whole.
          if (received > maxBytes) return null;
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (!isMediaFile(temp)) {
        mainLog.w('VideoCache: response for $url is not media');
        return null;
      }

      final name = '$key$extension';
      final dest = File(p.join(dir.path, name));
      if (dest.existsSync()) await dest.delete();
      await temp.rename(dest.path);
      temp = null;

      return await _exclusive(() async {
        await _ensureLoaded();
        _entries[key] = _CacheEntry(
          url: url,
          file: name,
          size: dest.lengthSync(),
          used: _now().millisecondsSinceEpoch,
        );
        await _evictToFit();
        await _writeIndex();
        // The freshly stored entry can be the one the cap evicts when it is
        // the largest thing in the cache; the caller then keeps streaming.
        return _entries.containsKey(key) ? dest : null;
      });
    } on DioException catch (e) {
      mainLog.w('VideoCache: failed to fetch $url', e);
      return null;
    } on FileSystemException catch (e) {
      mainLog.w('VideoCache: failed to write the cache for $url', e);
      return null;
    } catch (e, stack) {
      mainLog.w('VideoCache: failed to cache $url', e, stack);
      return null;
    } finally {
      final leftover = temp;
      if (leftover != null && leftover.existsSync()) {
        try {
          await leftover.delete();
        } catch (_) {
          // A partial left behind is pruned on the next load.
        }
      }
    }
  }

  /// Deletes the least recently used entries until the cache fits [maxBytes].
  Future<void> _evictToFit() async {
    final dir = await _ensureDir();
    var total = _entries.values.fold<int>(0, (sum, entry) => sum + entry.size);
    while (total > maxBytes && _entries.isNotEmpty) {
      final oldest = _entries.entries.reduce(
        (a, b) => a.value.used <= b.value.used ? a : b,
      );
      final entry = _entries.remove(oldest.key)!;
      total -= entry.size;
      try {
        final file = File(p.join(dir.path, entry.file));
        if (file.existsSync()) await file.delete();
      } catch (e) {
        // The entry is gone from the index; an undeletable file is pruned as
        // an orphan on the next load.
        mainLog.w('VideoCache: failed to evict ${entry.file}', e);
      }
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    // Marked before the first await: a second caller entering behind the
    // serial queue would otherwise start a parallel index read.
    _loaded = true;

    final dir = await _ensureDir();
    final index = File(p.join(dir.path, _indexName));
    if (index.existsSync()) {
      try {
        final raw = jsonDecode(await index.readAsString()) as Map;
        final entries = raw['entries'] as Map;
        for (final row in entries.entries) {
          final value = row.value as Map;
          final entry = _CacheEntry(
            url: value['url'] as String,
            file: value['file'] as String,
            size: (value['size'] as num).toInt(),
            used: (value['used'] as num).toInt(),
          );
          _entries[row.key as String] = entry;
        }
      } catch (e) {
        // An unreadable index is treated as an empty cache: the media files
        // it pointed at become orphans and are pruned below.
        mainLog.w('VideoCache: unreadable index', e);
        _entries.clear();
      }
    }

    await _pruneOrphans();
    await _evictToFit();
    await _writeIndex();
  }

  /// Deletes files the index does not point at, including the partial files a
  /// killed download leaves behind.
  Future<void> _pruneOrphans() async {
    final dir = await _ensureDir();
    final keep = _entries.values.map((entry) => entry.file).toSet();
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (p.basename(entity.path) == _indexName) continue;
      if (keep.contains(p.basename(entity.path))) continue;
      try {
        await entity.delete();
      } catch (e) {
        mainLog.w('VideoCache: failed to prune ${entity.path}', e);
      }
    }
  }

  Future<void> _writeIndex() async {
    try {
      final dir = await _ensureDir();
      final index = File(p.join(dir.path, _indexName));
      final temp = File('${index.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': _indexVersion,
          'entries': {
            for (final row in _entries.entries) row.key: row.value.toJson(),
          },
        }),
        flush: true,
      );
      await temp.rename(index.path);
    } on FileSystemException catch (e) {
      mainLog.w('VideoCache: failed to write the index', e);
    }
  }

  Future<Directory> _ensureDir() async {
    final cached = _dir;
    if (cached != null) return cached;

    final dir = await _directory();
    if (!dir.existsSync()) await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static bool _isMarkupContentType(String? raw) {
    final type = raw?.split(';').first.trim().toLowerCase();
    if (type == null || type.isEmpty) return false;
    return type.startsWith('text/') ||
        type == 'application/json' ||
        type == 'application/xml' ||
        type == 'application/xhtml+xml';
  }

  /// Extension for the cached file: the URL usually names it, and a server
  /// that hides the name behind a query still reports the container.
  static String _extensionFor(Uri uri, String? contentType) {
    const known = {'.mp4', '.m4v', '.mov', '.webm', '.mkv', '.gif'};
    final fromUrl = p.extension(uri.path).toLowerCase();
    if (known.contains(fromUrl)) return fromUrl;

    final type = contentType?.split(';').first.trim().toLowerCase();
    return switch (type) {
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      'video/quicktime' => '.mov',
      'video/x-matroska' => '.mkv',
      'image/gif' => '.gif',
      _ => '.bin',
    };
  }
}

/// One reading of the cache: [bytes] on disk across [count] videos.
class VideoCacheStats {
  const VideoCacheStats({required this.bytes, required this.count});

  static const empty = VideoCacheStats(bytes: 0, count: 0);

  final int bytes;
  final int count;
}

class _CacheEntry {
  _CacheEntry({
    required this.url,
    required this.file,
    required this.size,
    required this.used,
  });

  final String url;
  final String file;
  final int size;

  /// Milliseconds since the epoch of the last play.
  int used;

  Map<String, Object> toJson() => {
    'url': url,
    'file': file,
    'size': size,
    'used': used,
  };
}
