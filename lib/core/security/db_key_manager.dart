import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Random 256-bit DB key kept in Keystore-backed secure storage.
/// Losing it (app data cleared) makes the DB unreadable → restore from backup.
class DbKeyManager {
  DbKeyManager(this._storage);

  static const _storageKey = 'db_key_v1';
  final FlutterSecureStorage _storage;

  Future<String> getOrCreateKey() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    // base64url: no quote characters, safe inside PRAGMA key '...'.
    final key = base64UrlEncode(bytes);
    await _storage.write(key: _storageKey, value: key);
    return key;
  }
}
