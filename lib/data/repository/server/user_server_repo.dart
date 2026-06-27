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
      if (server.tagSuggestionUrl == oldDapiUrl ||
          server.tagSuggestionUrl == oldAutocompleteUrl) {
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

  @override
  Future<void> populate() async {
    if (_defaults.isEmpty) return;

    if (box.isEmpty) {
      await box.putAll(_defaults);
    } else {
      await _migrateKeys();
      await _migrateGelbooruSuggestionUrl();
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
    try {
      final List maps = jsonDecode(src);
      if (maps.isEmpty) return;
      await box.deleteAll(box.keys);
      for (final map in maps) {
        if (map is Map<String, dynamic>) {
          final server = Server.fromJson(map);
          await add(server);
        }
      }
      // Run migrations after import to fix any outdated server configs
      await _migrateGelbooruSuggestionUrl();
    } catch (e) {
      // Import failed, leave existing data intact
    }
  }

  @override
  Future<BackupItem> export() async {
    return BackupItem(key, box.values.map((e) {
      final json = e.toJson();
      json['login'] = '';
      json['apiKey'] = '';
      return json;
    }).toList());
  }

  static const String key = 'server';

  static Future<void> prepare() async {
    final cipher = await EncryptionHelper.getCipher();

    try {
      await Hive.openBox<Server>(key, encryptionCipher: cipher);
    } catch (_) {
      // Migration: old data was unencrypted
      final plainBox = await Hive.openBox<Server>(key);
      final data = plainBox.toMap();
      await plainBox.close();

      await Hive.deleteBoxFromDisk(key);

      final encryptedBox =
          await Hive.openBox<Server>(key, encryptionCipher: cipher);
      await encryptedBox.putAll(data);
      await encryptedBox.flush();
    }
  }
}
