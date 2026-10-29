import 'dart:convert';

import 'package:boorusphere/data/encryption.dart';
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

  /// Migrate Gelbooru-engine servers to use autocomplete2 endpoint for suggestions
  /// instead of the DAPI tag endpoint which has UTF-8 encoding issues.
  Future<void> _migrateGelbooruSuggestionUrl() async {
    const oldDapiUrl =
        'index.php?page=dapi&s=tag&q=index&name_pattern=%{tag-part}%&orderby=count&limit={post-limit}&json=1';
    const oldAutocompleteUrl = 'autocomplete.php?q={tag-part}';
    const newAutocompleteUrl =
        'index.php?page=autocomplete2&term={tag-part}&type=tag_query&limit={post-limit}';

    final mapped = Map<String, Server>.from(box.toMap());
    for (final entry in mapped.entries) {
      final server = entry.value;
      // Safebooru serves that autocomplete path itself, so its entry is not a
      // Gelbooru one wearing the same template.
      final isStaleAutocomplete =
          server.tagSuggestionUrl == oldAutocompleteUrl &&
          !_isSafebooru(server);
      if (server.tagSuggestionUrl == oldDapiUrl || isStaleAutocomplete) {
        await box.put(
          entry.key,
          server.copyWith(
            tagSuggestionUrl: newAutocompleteUrl,
            suggestionParserId: '', // Reset to auto-detect
          ),
        );
      }
    }
    await box.flush();
  }

  /// Restores Safebooru's own autocomplete URL on entries the Gelbooru
  /// rewrite above already converted, where it answers with the homepage
  /// instead of a tag list.
  Future<void> _migrateSafebooruSuggestionUrl() async {
    const autocompleteUrl = 'autocomplete.php?q={tag-part}';
    const gelbooruAutocompleteUrl =
        'index.php?page=autocomplete2&term={tag-part}&type=tag_query&limit={post-limit}';

    final mapped = Map<String, Server>.from(box.toMap());
    for (final entry in mapped.entries) {
      final server = entry.value;
      final wasRewritten = server.tagSuggestionUrl == gelbooruAutocompleteUrl;
      if (!wasRewritten || !_isSafebooru(server)) continue;

      await box.put(
        entry.key,
        server.copyWith(
          tagSuggestionUrl: autocompleteUrl,
          suggestionParserId: '',
        ),
      );
    }
    await box.flush();
  }

  bool _isSafebooru(Server server) {
    final host = Uri.tryParse(server.homepage)?.host ?? '';
    return host == 'safebooru.org' || host.endsWith('.safebooru.org');
  }

  /// Rule34 serves its API from its own host, which also rejects anonymous
  /// requests. Entries still pointing at the homepage only ever get a challenge
  /// page back.
  Future<void> _migrateRule34ApiHost() async {
    const homepage = 'https://rule34.xxx';
    const apiAddr = 'https://api.rule34.xxx';
    const searchUrl =
        'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}';
    const tagSuggestionUrl =
        'index.php?page=dapi&s=tag&q=index&name_pattern=%{tag-part}%&orderby=count&limit={post-limit}';

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
          tagSuggestionUrl: tagSuggestionUrl,
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

  @override
  Future<void> populate() async {
    if (_defaults.isEmpty) return;

    if (box.isEmpty) {
      await box.putAll(_defaults);
    } else {
      await _migrateKeys();
      await _migrateGelbooruSuggestionUrl();
      await _migrateSafebooruSuggestionUrl();
      await _migrateRule34ApiHost();
      await _migrateOneBasedPageParam();
    }
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
    await _migrateGelbooruSuggestionUrl();
    await _migrateSafebooruSuggestionUrl();
    await _migrateRule34ApiHost();
    await _migrateOneBasedPageParam();
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
