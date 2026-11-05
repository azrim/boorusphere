import 'dart:convert';

import 'package:boorusphere/data/encryption.dart';
import 'package:boorusphere/data/repository/booru/parser/autocomplete.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/e621_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_autocomplete_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/repository/server_data_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:hive_ce/hive.dart';

class UserServerRepo implements ServerRepo {
  UserServerRepo({
    required Map<String, Server> defaultServers,
    required this.box,
  }) : _defaults = defaultServers;

  final Map<String, Server> _defaults;
  final Box<Server> box;

  @override
  List<Server> get servers => box.values.toList();

  @override
  Map<String, Server> get defaults => _defaults;

  Future<void> _migrateKeys() async {
    final mapped = Map<String, Server>.from(box.toMap());
    for (final data in mapped.entries) {
      if (data.key.startsWith('@')) {
        continue;
      }
      await box.delete(data.key);
      await box.put(data.value.key, data.value);
    }
    await box.flush();
  }

  /// The tag endpoint each known host actually answers, with the parser that
  /// reads it.
  ///
  /// Gelbooru, Safebooru and Rule34 share a code base and not an API: the first
  /// moved its tag list to `autocomplete2`, the other two still answer from
  /// `autocomplete.php`, and Rule34's `dapi` tag endpoint asks an anonymous
  /// client for an account. Danbooru and e621 both served suggestions as a
  /// sorted sweep of the tag table where the site offers a completion endpoint
  /// built for the keystroke that asks. The template that replaces an outdated
  /// one therefore depends on the host that sent it, and is read from the parser
  /// that serves it so the table cannot drift from the engine. Three passes each
  /// assumed their own answer was right for everybody, which is how two of these
  /// hosts ended up asking for a tag list they never return.
  Future<void> _migrateSuggestionUrl() async {
    final endpoints = <_SiteHost, BooruParser>{
      _SiteHost.gelbooru: GelbooruAutocompleteParser(),
      _SiteHost.safebooru: AutocompleteJsonParser(),
      _SiteHost.rule34: AutocompleteJsonParser(),
      _SiteHost.danbooru: DanbooruJsonParser(),
      _SiteHost.e621: E621JsonParser(),
    };
    // The DAPI tag endpoint, in both the XML and the JSON dialect it was
    // handed out in, and the tag-table sweep the completion endpoints replaced.
    const retired = {
      'index.php?page=dapi&s=tag&q=index&name_pattern=%{tag-part}%'
          '&orderby=count&limit={post-limit}',
      'index.php?page=dapi&s=tag&q=index&name_pattern=%{tag-part}%'
          '&orderby=count&limit={post-limit}&json=1',
      'tags.json?search[name_matches]=*{tag-part}*&search[order]=count'
          '&limit={post-limit}',
    };
    final outdated = {
      ...retired,
      ...endpoints.values.map((it) => it.suggestionQuery),
    };

    final mapped = Map<String, Server>.from(box.toMap());
    for (final entry in mapped.entries) {
      final server = entry.value;
      if (!outdated.contains(server.tagSuggestionUrl)) continue;

      // A site this app has no table for keeps what its owner configured:
      // guessing an endpoint for it is how the passes this replaced went wrong
      // for the sites it did recognize.
      final parser = endpoints[_siteHost(server)];
      if (parser == null) continue;
      if (parser.suggestionQuery.isEmpty) continue;
      if (server.tagSuggestionUrl == parser.suggestionQuery &&
          server.suggestionParserId == parser.id) {
        continue;
      }

      await box.put(
        entry.key,
        server.copyWith(
          tagSuggestionUrl: parser.suggestionQuery,
          // The endpoint names its own dialect: the payload two of these hosts
          // return is the same set of keys, so which parser reads it decides
          // whether the post count and the tag category survive the trip.
          suggestionParserId: parser.id,
        ),
      );
    }
    await box.flush();
  }

  /// The site family [server] points at, read from either of its addresses: an
  /// entry edited onto its API host is still the same site.
  _SiteHost? _siteHost(Server server) {
    for (final address in [server.homepage, server.apiAddr]) {
      final host = Uri.tryParse(address)?.host ?? '';
      if (host.isEmpty) continue;
      if (host == 'gelbooru.com' || host.endsWith('.gelbooru.com')) {
        return _SiteHost.gelbooru;
      }
      if (host == 'safebooru.org' || host.endsWith('.safebooru.org')) {
        return _SiteHost.safebooru;
      }
      if (host == 'rule34.xxx' || host.endsWith('.rule34.xxx')) {
        return _SiteHost.rule34;
      }
      if (host == 'danbooru.donmai.us') return _SiteHost.danbooru;
      if (host == 'e621.net') return _SiteHost.e621;
    }
    return null;
  }

  /// Rule34 serves its API from its own host, which also rejects anonymous
  /// requests. Entries still pointing at the homepage only ever get a challenge
  /// page back.
  ///
  /// Its suggestion template is left to [_migrateSuggestionUrl]: that host
  /// answers a tag list from `autocomplete.php` and not from the endpoint the
  /// site it was cloned from moved to.
  Future<void> _migrateRule34ApiHost() async {
    const homepage = 'https://rule34.xxx';
    const apiAddr = 'https://api.rule34.xxx';
    const searchUrl =
        'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}';

    final mapped = Map<String, Server>.from(box.toMap());
    for (final entry in mapped.entries) {
      final server = entry.value;
      final isRule34 =
          server.homepage.replaceFirst(RegExp(r'/+$'), '') == homepage;
      if (!isRule34 || server.apiAddr.isNotEmpty) {
        continue;
      }

      await box.put(
        entry.key,
        server.copyWith(
          apiAddr: apiAddr,
          searchUrl: searchUrl,
          searchParserId: '', // Reset to auto-detect
          suggestionParserId: '',
        ),
      );
    }
    await box.flush();
  }

  /// One-based engines (Danbooru and its clones) were fed the zero-based page
  /// index, so page 0 and page 1 answered with the same posts. Rewrite the
  /// preset templates to the one-based placeholder; hand-written URLs are left
  /// alone.
  Future<void> _migrateOneBasedPageParam() async {
    const outdated = {
      'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
      'post.json?tags={tags}&page={page-id}&limit={post-limit}',
      'api/v1/json/search/images?q={tags}&per_page={post-limit}&page={page-id}',
      'api/v1/json/search/images?q={tags}&page={page-id}&per_page={post-limit}',
      'api/danbooru/find_posts/index.xml?tags={tags}&limit={post-limit}&page={page-id}',
    };

    final mapped = Map<String, Server>.from(box.toMap());
    for (final entry in mapped.entries) {
      if (!outdated.contains(entry.value.searchUrl)) continue;
      await box.put(
        entry.key,
        entry.value.copyWith(
          searchUrl: entry.value.searchUrl.replaceAll(
            'page={page-id}',
            'page={page-num}',
          ),
        ),
      );
    }
    await box.flush();
  }

  /// Shimmie's `danbooru_api` extension answers under its clean path: the
  /// `/index.xml` suffix these entries still carry resolves to the site's error
  /// page, which no parser reads, so every search on such an entry fails.
  Future<void> _migrateShimmieSearchPath() async {
    const stalePath = 'api/danbooru/find_posts/index.xml';
    const currentPath = 'api/danbooru/find_posts';

    final mapped = Map<String, Server>.from(box.toMap());
    for (final entry in mapped.entries) {
      final server = entry.value;
      if (!server.searchUrl.contains(stalePath)) continue;

      await box.put(
        entry.key,
        server.copyWith(
          searchUrl: server.searchUrl.replaceFirst(stalePath, currentPath),
        ),
      );
    }
    await box.flush();
  }

  @override
  Future<void> populate() async {
    if (_defaults.isEmpty) return;

    if (box.isEmpty) {
      await box.putAll(_defaults);
    } else {
      await _migrateKeys();
      await _healOutdatedEntries();
    }
  }

  /// Every pass that fixes an entry an older release wrote.
  ///
  /// Both the start-up path and a restore run the same set: a backup is as
  /// outdated as the box it came from, and a list restored on a newer build
  /// must not keep an endpoint this release already knows is dead.
  Future<void> _healOutdatedEntries() async {
    await _migrateRule34ApiHost();
    await _migrateSuggestionUrl();
    await _migrateOneBasedPageParam();
    await _migrateShimmieSearchPath();
  }

  @override
  Future<void> add(Server data) async {
    await box.put(
      data.key,
      data.apiAddr == data.homepage ? data.copyWith(apiAddr: '') : data,
    );
  }

  @override
  Future<Server> edit(Server from, Server to) async {
    final data = to.apiAddr == to.homepage
        ? to.copyWith(id: from.id, apiAddr: '')
        : to.copyWith(id: from.id);

    await box.put(from.key, data);
    return data;
  }

  @override
  Future<void> reset() async {
    await box.deleteAll(box.keys);
    await box.putAll(_defaults);
  }

  @override
  Future<void> remove(Server data) async {
    await box.delete(data.key);
  }

  @override
  Future<void> import(String src) async {
    final List maps;
    try {
      maps = jsonDecode(src) as List;
    } catch (e) {
      // Not a server backup; leave the existing data intact.
      return;
    }
    if (maps.isEmpty) return;

    // Decode every entry before touching the box: a malformed entry used to
    // abort the loop after the box had already been cleared, leaving the user
    // with a partial server list.
    final restored = <String, Server>{};
    try {
      for (final map in maps) {
        if (map is! Map<String, dynamic>) continue;
        final server = Server.fromJson(map);
        restored[server.key] = server.apiAddr == server.homepage
            ? server.copyWith(apiAddr: '')
            : server;
      }
    } catch (e) {
      return;
    }
    if (restored.isEmpty) return;

    // The new entries reach the disk before the ones the backup does not
    // mention are dropped, so a failed write never leaves an empty list.
    await box.putAll(restored);
    final stale = box.keys.where((it) => !restored.containsKey(it)).toList();
    if (stale.isNotEmpty) await box.deleteAll(stale);
    await box.flush();

    // Run migrations after import to fix any outdated server configs
    await _healOutdatedEntries();
  }

  /// Exports the servers with their credentials, so restoring on a new device
  /// does not ask the user to sign in again. The archive can still be encrypted
  /// through the backup encryption option.
  @override
  Future<BackupItem> export() async {
    return BackupItem(key, box.values.map((e) => e.toJson()).toList());
  }

  static const String key = 'server';

  /// Box holding a copy of the entries while the plain box is rewritten as an
  /// encrypted one. One that survives a start means that migration stopped
  /// before the encrypted box was complete.
  static const String _migrationKey = 'server_migration';

  static Future<void> prepare() async {
    final cipher = await EncryptionHelper.getCipher();
    await _recoverInterruptedMigration(cipher);

    try {
      await Hive.openBox<Server>(key, encryptionCipher: cipher);
      return;
    } catch (_) {
      // Migration: old data was unencrypted.
      final data = await _readUnencrypted();
      if (data == null) {
        // The box is on disk but neither the encryption key nor a plain read
        // opens it, which means the stored entries are unrecoverable. They are
        // left untouched: the app starts with an empty list and reports the
        // failure instead of deleting data it cannot read.
        rethrow;
      }

      await _migrateToEncrypted(data, cipher);
    }
  }

  /// Rewrites the plain box as an encrypted one.
  ///
  /// The entries are copied to an encrypted box under [_migrationKey] before
  /// the plain box is dropped: that copy is the only one left between the two
  /// steps, and it carries the server list with its credentials.
  static Future<void> _migrateToEncrypted(
    Map<dynamic, Server> data,
    HiveAesCipher cipher,
  ) async {
    final migration = await Hive.openBox<Server>(
      _migrationKey,
      encryptionCipher: cipher,
    );
    await migration.putAll(data);
    await migration.flush();
    await migration.close();

    await Hive.deleteBoxFromDisk(key);

    final encryptedBox = await Hive.openBox<Server>(
      key,
      encryptionCipher: cipher,
    );
    await encryptedBox.putAll(data);
    await encryptedBox.flush();

    await Hive.deleteBoxFromDisk(_migrationKey);
  }

  /// Writes back the copy left by an interrupted migration, then drops it.
  ///
  /// Runs before the box is opened, so a start that follows a half-finished
  /// migration finds its server list instead of an empty box. The handle is
  /// closed afterwards so the cipher is still applied when the box is plain.
  static Future<void> _recoverInterruptedMigration(HiveAesCipher cipher) async {
    if (!await Hive.boxExists(_migrationKey)) return;

    final migration = await Hive.openBox<Server>(
      _migrationKey,
      encryptionCipher: cipher,
    );
    final data = migration.toMap();
    await migration.close();

    if (data.isEmpty) {
      await Hive.deleteBoxFromDisk(_migrationKey);
      return;
    }

    final restored = await _openForRestore(cipher);
    await restored.putAll(data);
    await restored.flush();
    await restored.close();

    await Hive.deleteBoxFromDisk(_migrationKey);
  }

  /// The server box, opened with the cipher when it is encrypted and plainly
  /// when it is still the legacy one.
  static Future<Box<Server>> _openForRestore(HiveAesCipher cipher) async {
    try {
      return await Hive.openBox<Server>(key, encryptionCipher: cipher);
    } catch (_) {
      return Hive.openBox<Server>(key);
    }
  }

  /// Reads the box without a cipher, or returns null when its entries are
  /// encrypted.
  static Future<Map<dynamic, Server>?> _readUnencrypted() async {
    try {
      final box = await Hive.openBox<Server>(key);
      final data = box.toMap();
      await box.close();
      return data;
    } catch (_) {
      return null;
    }
  }
}

/// The site families this release knows the tag endpoint of.
enum _SiteHost { gelbooru, safebooru, rule34, danbooru, e621 }
