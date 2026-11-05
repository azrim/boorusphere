import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';

abstract interface class ServerRepo {
  Iterable<Server> get servers;
  Map<String, Server> get defaults;
  Future<void> populate();
  Future<void> add(Server data);
  Future<Server> edit(Server from, Server to);
  Future<void> remove(Server data);
  Future<void> reset();

  /// Restores [src] and reports how many servers it carried, or null when the
  /// payload is not a server list. An empty list is zero: the archive named an
  /// empty store, and the stored list is emptied to match.
  Future<int?> import(String src);
  Future<BackupItem> export();
}
