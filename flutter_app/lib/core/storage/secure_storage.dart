import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyRefreshToken = 'refresh_token';
  static const _keyDeviceId = 'device_id';

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _keyRefreshToken, value: token);

  Future<String?> readRefreshToken() => _storage.read(key: _keyRefreshToken);

  Future<void> deleteRefreshToken() => _storage.delete(key: _keyRefreshToken);

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
