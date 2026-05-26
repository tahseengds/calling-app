import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  static const _keyRefreshToken = 'refresh_token';
  static const _keyDeviceId = 'device_id';
  static const _keyCachedUser = 'cached_user_json';

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _keyRefreshToken, value: token);

  Future<String?> readRefreshToken() => _storage.read(key: _keyRefreshToken);

  Future<void> deleteRefreshToken() => _storage.delete(key: _keyRefreshToken);

  /// Persist the authenticated user so session restore can render the home
  /// screen immediately even when the network is unreachable. We never trust
  /// this for authorization decisions — the access token from /api/auth/refresh
  /// is the source of truth — but it keeps the user from being bounced to the
  /// login screen on a transient connection blip.
  Future<void> saveCachedUserJson(String json) =>
      _storage.write(key: _keyCachedUser, value: json);

  Future<Map<String, dynamic>?> readCachedUser() async {
    final raw = await _storage.read(key: _keyCachedUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  Future<void> deleteCachedUser() => _storage.delete(key: _keyCachedUser);

  // Generates a UUID device id on first run and persists it for the lifetime of
  // the app install. Used by auth and refresh endpoints to bind sessions to devices.
  Future<String> readDeviceId() async {
    var id = await _storage.read(key: _keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _keyDeviceId, value: id);
    }
    return id;
  }
}

final secureStorageProvider = Provider<SecureStorageService>(
  (_) => SecureStorageService(),
);
