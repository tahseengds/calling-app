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

    // Single-flight refresh — TokenInterceptor serializes concurrent 401s
    // inside this interceptor, and the AuthNotifier.refreshInFlight check
    // below serializes against the cold-start auth-restore path so the
    // two never POST /api/auth/refresh with the same token in parallel
    // (which would trip the backend's reuse-detection and revoke every
    // session for the user).
    refreshTokens: () async {
      refreshWasAuthRejected = false;

      // ── Cold-start race guard ──────────────────────────────────────
      // If AuthNotifier is in the middle of restoring (it ran its own
      // refresh between cache restore and the optimistic
      // AuthAuthenticated), wait for it instead of POSTing a parallel
      // refresh with the same token.
      final authPending =
          ref.read(authNotifierProvider.notifier).refreshInFlight;
      if (authPending != null) {
        final ok = await authPending;
        if (ok && ref.read(authTokenProvider) != null) {
          return true;
        }
        // AuthNotifier already decided this session is dead — don't
        // double-trip its bookkeeping by also flagging refreshWasAuthRejected.
        return false;
      }

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
    // are deliberately treated as "try again later", and a cold-start race
    // where AuthNotifier is still resolving the session shouldn't yank the
    // user to /login mid-restore.
    onAuthExpired: () {
      if (AppConfig.uiOnly) return;
      if (!refreshWasAuthRejected) return;
      // Belt-and-suspenders: if AuthNotifier is still restoring, defer to
      // its outcome — its rotated refresh-token may already be saved and
      // forceSignOut would wipe it.
      if (ref.read(authNotifierProvider.notifier).refreshInFlight != null) {
        return;
      }
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
