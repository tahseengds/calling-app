import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_token.dart';
import '../config/app_config.dart';
import '../storage/secure_storage.dart';
import 'token_interceptor.dart';
// auth_notifier is imported for forceSignOut only — auth_repository does NOT
// import dio_client, so there is no circular dependency.
import '../../features/auth/domain/auth_notifier.dart';

final dioProvider = Provider<Dio>((ref) {
  final secure = ref.read(secureStorageProvider);

  final interceptor = TokenInterceptor(
    // Read the in-memory access token (never from disk).
    getAccessToken: () => ref.read(authTokenProvider),

    // Single-flight refresh — TokenInterceptor serializes concurrent 401s.
    refreshTokens: () async {
      final savedRefresh = await secure.readRefreshToken();
      final deviceId = await secure.readDeviceId();
      if (savedRefresh == null) return false;
      try {
        final plain = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiBaseUrl,
            headers: {'Content-Type': 'application/json'},
          ),
        );
        final resp = await plain.post<Map<String, dynamic>>(
          '/api/auth/refresh',
          data: {'refresh_token': savedRefresh, 'device_id': deviceId},
        );
        final newAccess = resp.data?['access_token'] as String?;
        final newRefresh = resp.data?['refresh_token'] as String?;
        if (newAccess == null || newRefresh == null) return false;
        ref.read(authTokenProvider.notifier).set(newAccess);
        await secure.saveRefreshToken(newRefresh);
        return true;
      } catch (_) {
        return false;
      }
    },

    // Called when refresh itself fails — wipe local auth and send to /login.
    onAuthExpired: () {
      if (AppConfig.uiOnly) return;
      ref.read(authNotifierProvider.notifier).forceSignOut();
    },
  );

  return Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  )..interceptors.add(interceptor);
});
