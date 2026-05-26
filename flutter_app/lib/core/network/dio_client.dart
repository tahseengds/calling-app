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

  // Captures whether the most-recent refresh attempt failed because the server
  // rejected the refresh token (401/403) vs. a transport-level error. We only
  // force the user back to /login on the former — otherwise a transient blip
  // (e.g. captive wifi, brief 5xx) silently nukes a valid session.
  bool refreshWasAuthRejected = false;

  final interceptor = TokenInterceptor(
    // Read the in-memory access token (never from disk).
    getAccessToken: () => ref.read(authTokenProvider),

    // Single-flight refresh — TokenInterceptor serializes concurrent 401s.
    refreshTokens: () async {
      refreshWasAuthRejected = false;
      final savedRefresh = await secure.readRefreshToken();
      final deviceId = await secure.readDeviceId();
      if (savedRefresh == null) {
        // No refresh token at all — treat as auth-rejected so the caller is
        // routed back to /login rather than spinning on stuck requests.
        refreshWasAuthRejected = true;
        return false;
      }
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
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        refreshWasAuthRejected = (code == 401 || code == 403);
        return false;
      } catch (_) {
        return false;
      }
    },

    // Called when refresh itself fails — but only force a sign-out when the
    // server actually rejected the refresh token. Transient transport errors
    // are deliberately treated as "try again later".
    onAuthExpired: () {
      if (AppConfig.uiOnly) return;
      if (refreshWasAuthRejected) {
        ref.read(authNotifierProvider.notifier).forceSignOut();
      }
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
