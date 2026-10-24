import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_data_state.g.dart';

@Riverpod(keepAlive: true)
class ServerState extends _$ServerState {
  @override
  Iterable<Server> build() {
    // populate later
    return [];
  }

  ServerSettingState get settings =>
      ref.read(serverSettingStateProvider.notifier);

  Future<void> populate() async {
    final serverSetting = ref.read(serverSettingStateProvider);
    final repo = ref.read(serverRepoProvider);
    await repo.populate();
    state = repo.servers;

    // An empty or stale id would leave the home session pointing at a server
    // that no longer exists; every lookup would then have to guess.
    if (state.isNotEmpty &&
        !state.any((it) => it.id == serverSetting.lastActiveId)) {
      final server = state.firstWhere(
        (it) => it.id.startsWith('Safe'),
        orElse: () => state.first,
      );
      await settings.setLastActiveId(server.id);
    }
  }

  /// Adds a server, refusing a name that resolves to an existing key.
  ///
  /// The key is derived from the name, so "My Site", "My-Site" and "my_site"
  /// all address the same entry, so saving one of them would replace the
  /// existing server, credentials included, without a word.
  Future<void> add(Server data) async {
    if (state.any((it) => it.key == data.key)) {
      throw ServerAlreadyExistsException(data);
    }

    final repo = ref.read(serverRepoProvider);
    await repo.add(data);
    state = repo.servers;
  }

  Future<void> remove(Server data) async {
    if (state.length == 1) {
      throw Exception('Last server cannot be deleted');
    }

    final repo = ref.read(serverRepoProvider);
    await repo.remove(data);
    state = repo.servers;

    // The removed server may be the one the session points at. Leaving its id
    // behind makes every lookup silently fall back to the first server, so the
    // next fetch answers from a different booru than the one on screen.
    if (state.isNotEmpty &&
        ref.read(serverSettingStateProvider).lastActiveId == data.id) {
      await settings.setLastActiveId(state.first.id);
    }
  }

  Future<void> edit(Server from, Server to) async {
    final repo = ref.read(serverRepoProvider);
    await repo.edit(from, to);
    state = repo.servers;
  }

  Future<void> reset() async {
    final repo = ref.read(serverRepoProvider);
    await repo.reset();
    state = repo.servers;
    if (state.isNotEmpty) {
      await settings.setLastActiveId(state.first.id);
    }
  }
}

/// Raised when a server name collides with an existing entry.
class ServerAlreadyExistsException implements Exception {
  const ServerAlreadyExistsException(this.server);

  final Server server;

  @override
  String toString() => 'ServerAlreadyExistsException(${server.key})';
}

extension ServerDataListExt on Iterable<Server> {
  Server getById(String id, {Server? or}) {
    return isEmpty
        ? Server.empty
        : firstWhere((it) => it.id == id, orElse: () => or ?? first);
  }
}
