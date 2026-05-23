import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/models/user.dart';

/// All auth API calls use a plain Dio instance with no interceptors.
/// Auth endpoints (/api/auth/*) don't need a Bearer token (except logout),
/// so we never import dio_client.dart here — that prevents a circular dep.
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

  // ── Login ─────────────────────────────────────────────────────────────────

  /// Validates credentials and triggers an OTP SMS.
  /// Returns the phone back plus an optional debug OTP (only in DEBUG builds).
  Future<({String phone, String? debugOtp})> requestLoginOtp({
    required String phone,
    required String password,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/auth/request-otp',
      data: {'phone': phone, 'password': password},
    );
    return (
      phone: phone,
      debugOtp: resp.data?['debug_otp'] as String?,
    );
  }

  // ── Register ──────────────────────────────────────────────────────────────

  /// Creates the account and triggers an OTP SMS for verification.
  Future<({String phone, String? debugOtp})> register({
    required String name,
    required String phone,
    required String password,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {'name': name, 'phone': phone, 'password': password},
    );
    return (
      phone: phone,
      debugOtp: resp.data?['debug_otp'] as String?,
    );
  }

  // ── OTP verification ──────────────────────────────────────────────────────

  /// Submits the 6-digit OTP and returns fresh tokens + the user object.
  Future<({String accessToken, String refreshToken, User me})> verifyOtp({
    required String phone,
    required String code,
    required String deviceId,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/auth/verify-otp',
      data: {'phone': phone, 'code': code, 'device_id': deviceId},
    );
    final data = resp.data!;
    return (
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      me: User.fromJson(data['user'] as Map<String, dynamic>),
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

  /// Fetches the authenticated user's profile. Called after session restore
  /// when the refresh response doesn't embed the user object.
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

  /// Invalidates the current device session on the server.
  Future<void> logout({
    required String accessToken,
    required String deviceId,
  }) async {
    await Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ),
    ).delete('/api/auth/logout', data: {'device_id': deviceId});
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(AppConfig.apiBaseUrl),
);
