import 'dart:async';

import '../models/credentials.dart';

/// Abstract interface for token storage.
abstract class TokenStorage {
  /// Reads credentials from storage.
  Future<Credentials?> read();

  /// Writes credentials to storage.
  Future<void> write(Credentials credentials);

  /// Deletes credentials from storage.
  Future<void> delete();

  /// Checks if credentials exist.
  Future<bool> hasCredentials() async {
    final credentials = await read();
    return credentials != null;
  }
}

/// Simple in-memory token storage useful for tests and quick starts.
class InMemoryTokenStorage extends TokenStorage {
  Credentials? _credentials;

  InMemoryTokenStorage({Credentials? initialCredentials})
      : _credentials = initialCredentials;

  @override
  Future<void> delete() async {
    _credentials = null;
  }

  @override
  Future<Credentials?> read() async => _credentials;

  @override
  Future<void> write(Credentials credentials) async {
    _credentials = credentials;
  }
}
