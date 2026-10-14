import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the Claude API key. Backed by Android Keystore-encrypted storage in
/// the app; tests swap in [InMemoryApiKeyStore]. The key is never logged,
/// persisted elsewhere, or kept in widget state longer than needed.
abstract class ApiKeyStore {
  Future<String?> read();
  Future<void> write(String key);
  Future<void> delete();
}

class SecureApiKeyStore implements ApiKeyStore {
  static const _storageKey = 'anthropic_api_key';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _storageKey);

  @override
  Future<void> write(String key) =>
      _storage.write(key: _storageKey, value: key);

  @override
  Future<void> delete() => _storage.delete(key: _storageKey);
}

class InMemoryApiKeyStore implements ApiKeyStore {
  InMemoryApiKeyStore([this._key]);

  String? _key;

  @override
  Future<String?> read() async => _key;

  @override
  Future<void> write(String key) async => _key = key;

  @override
  Future<void> delete() async => _key = null;
}
