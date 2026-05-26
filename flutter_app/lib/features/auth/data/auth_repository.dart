import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/models/user.dart';

/// All auth API calls use a plain Dio instance with no interceptors.
/// Auth endpoints (/api/auth/*) don't need a Bearer token (except logout),
/// so we never import dio_client.dart here — that prevents a circular dep.
///
/// Outbound endpoints:
///   - POST /api/auth/firebase-signin  (trade Firebase ID token → our tokens;
///                                      works for Google or email/password)
///   - POST /api/auth/refresh
///   - POST /api/auth/logout           (Bearer required)
///   - GET  /api/users/me
class AuthRepository {
  final Dio _dio;

  AuthRepository(String baseUrl)
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

  // ── Firebase sign-in ───────────────────────────────────────────────────────

  /// Trade a Firebase ID token (Google or email/password) for our access
  /// + refresh JWTs.
  ///
  /// The client must have already completed sign-in on the Firebase side
  /// (signInWithCredential / signInWithEmailAndPassword) and obtained an
  /// ID token via FirebaseUser.getIdToken().
  ///
  /// [name] is only used on a first-time sign-in for the welcome step; the
  /// backend ignores it for returning users.
  Future<({String accessToken, String refreshToken})> firebaseSignIn({
    required String firebaseIdToken,
    required String deviceId,
    String? fcmToken,
    String? name,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/auth/firebase-signin',
      data: {
        'firebase_id_token': firebaseIdToken,
        'device_id': deviceId,
        'fcm_token': ?fcmToken,
        // name is only sent when truly non-empty (avoid sending '' to the
        // backend, which would skip its default-name fallback).
        if (name != null && name.isNotEmpty) 'name': name,
      },
    );
    final data = resp.data!;
    return (
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  /// Exchanges the stored refresh token for a new access + refresh pair.
  Future<({String accessToken, String refreshToken})> refreshAccessToken({
    required String refreshToken,
    required String deviceId,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/auth/refresh',
      data: {'refresh_token': refreshToken, 'device_id': deviceId},
    );
    final data = resp.data!;
    return (
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );
  }

  // ── Current user ──────────────────────────────────────────────────────────

  /// Fetches the authenticated user's profile. Called after firebase-signin
  /// (which returns tokens only) and after session restore.
  Future<User> getMe(String accessToken) async {
    final resp = await Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ),
    ).get<Map<String, dynamic>>('/api/users/me');
    return User.fromJson(resp.data!);
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  /// Invalidates the current refresh-token row on the server.
  ///
  /// Backend wants: POST /api/auth/logout, Bearer header,
  ///                JSON body {refresh_token: "..."}.
  Future<void> logout({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ),
    ).post<void>(
      '/api/auth/logout',
      data: {'refresh_token': refreshToken},
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(AppConfig.apiBaseUrl),
);
