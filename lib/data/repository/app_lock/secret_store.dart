import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The string secrets the app keeps outside the Hive boxes.
///
/// Narrow on purpose: the app lock is the only secret so far, and a small
/// interface lets tests run the repository without the platform channel.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecretStore implements SecretStore {
  const FlutterSecretStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
