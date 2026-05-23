import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the in-memory access token only. This is the bridge between the Dio
/// interceptor (core/network) and the auth feature so that neither layer needs
/// to import the other and create a circular dependency.
///
/// The refresh token lives in flutter_secure_storage (SecureStorageService).
/// The access token MUST never be persisted to disk.
class AuthTokenNotifier extends StateNotifier<String?> {
  AuthTokenNotifier() : super(null);

  void set(String token) => state = token;
  void clear() => state = null;
}

final authTokenProvider =
    StateNotifierProvider<AuthTokenNotifier, String?>(
  (_) => AuthTokenNotifier(),
);
