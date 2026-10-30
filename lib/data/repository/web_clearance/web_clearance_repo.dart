import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// A session the in-app browser solved, kept so the API client can reuse it.
///
/// Some servers answer every client that cannot run JavaScript with a
/// challenge page. Once the user has answered it in the WebView, the clearance
/// cookie and the browser's User-Agent are the two things that must travel
/// together: Cloudflare ties the cookie to the agent that earned it, so sending
/// one without the other is challenged again.
@immutable
class WebClearance {
  const WebClearance({required this.userAgent, required this.cookies});

  /// The exact User-Agent the browser sent while earning [cookies].
  final String userAgent;

  /// The cookies as they came back from the browser, `name=value; name=value`.
  final String cookies;

  String encode() => jsonEncode({'ua': userAgent, 'cookie': cookies});

  /// Reads an entry, or null when the stored value predates this format or was
  /// written by hand.
  static WebClearance? tryParse(Object? raw) {
    if (raw is! String) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final userAgent = data['ua'];
      final cookies = data['cookie'];
      if (userAgent is! String || cookies is! String) return null;
      if (userAgent.isEmpty || cookies.isEmpty) return null;
      return WebClearance(userAgent: userAgent, cookies: cookies);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WebClearance &&
      other.userAgent == userAgent &&
      other.cookies == cookies;

  @override
  int get hashCode => Object.hash(userAgent, cookies);
}

/// Stores one [WebClearance] per host.
///
/// Entries also cover the host's subdomains: the API and the image CDN of the
/// same site are separate origins, and the browser usually clears both at once.
class WebClearanceRepo {
  WebClearanceRepo(this.box);

  /// The open box, or null when boot could not open it. A missing box only
  /// costs persistence — the clearance still works for this run.
  final Box<String>? box;

  /// Values read from [box], parsed once. Hive keeps the entries in memory, so
  /// every request can ask without touching the disk.
  Map<String, WebClearance>? _entries;

  /// Values written while [box] is unavailable or a write failed.
  final Map<String, WebClearance> _memory = {};

  static const String key = 'web_clearance';

  static WebClearanceRepo open() {
    return WebClearanceRepo(Hive.isBoxOpen(key) ? Hive.box<String>(key) : null);
  }

  static Future<void> prepare() => Hive.openBox<String>(key);

  /// The entry whose host is [host] or one of its parents, preferring the most
  /// specific one (the longest match), or null when nothing was solved for it.
  WebClearance? forHost(String host) {
    final target = host.toLowerCase();
    if (target.isEmpty) return null;

    final entries = _read();
    WebClearance? match;
    var matchLength = -1;
    for (final entry in entries.entries) {
      final rule = entry.key.toLowerCase();
      final applies = target == rule || target.endsWith('.$rule');
      if (!applies || rule.length <= matchLength) continue;
      match = entry.value;
      matchLength = rule.length;
    }
    return match;
  }

  /// Remembers what the browser earned for [host].
  Future<void> save({
    required String host,
    required String userAgent,
    required String cookies,
  }) async {
    if (host.isEmpty || userAgent.isEmpty || cookies.isEmpty) return;
    final clearance = WebClearance(userAgent: userAgent, cookies: cookies);
    _read()[host] = clearance;
    _memory[host] = clearance;

    final target = box;
    if (target == null) return;
    try {
      await target.put(host, clearance.encode());
      _memory.remove(host);
    } catch (e, stack) {
      debugPrint('WebClearance: failed to store "$host": $e\n$stack');
    }
  }

  Map<String, WebClearance> _read() {
    final cached = _entries;
    if (cached != null) {
      cached.addAll(_memory);
      return cached;
    }

    final entries = <String, WebClearance>{};
    final target = box;
    if (target != null) {
      for (final key in target.keys) {
        final parsed = WebClearance.tryParse(target.get(key));
        if (parsed != null) entries['$key'] = parsed;
      }
    }
    entries.addAll(_memory);
    return _entries = entries;
  }
}
