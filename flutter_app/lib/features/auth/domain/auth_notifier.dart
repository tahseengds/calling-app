import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_token.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final SecureStorageService _secure;
  final Ref _ref;

  AuthNotifier(this._repo, this._secure, this._ref)
      : super(const AuthUnknown()) {
    _tryRestoreSession();
  }

  // ── Session restore ───────────────────────────────────────────────────────

  Future<void> _tryRestoreSession() async {
    final savedRefresh = await _secure.readRefreshToken();
    if (savedRefresh == null) {
      state = const AuthUnauthenticated();
      return;
    }
    try {
      final deviceId = await _secure.readDeviceId();
      final tokens = await _repo.refreshAccessToken(
        refreshToken: savedRefresh,
        deviceId: deviceId,
      );
      _ref.read(authTokenProvider.notifier).set(tokens.accessToken);
      await _secure.saveRefreshToken(tokens.refreshToken);
      final me = await _repo.getMe(tokens.accessToken);
      state = AuthAuthenticated(me: me);
    } catch (_) {
      await _secure.deleteRefreshToken();
      _ref.read(authTokenProvider.notifier).clear();
      state = const AuthUnauthenticated();
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  /// Validates credentials and requests an OTP. Throws on failure so the
  /// screen can display a Snackbar without changing global auth state.
  Future<void> requestLoginOtp({
    required String phone,
    required String password,
  }) async {
    final result = await _repo.requestLoginOtp(
      phone: phone,
      password: password,
    );
    state = AuthOtpPending(phone: result.phone, debugOtp: result.debugOtp);
  }

  // ── Register ──────────────────────────────────────────────────────────────

  Future<void> register({
    required String name,
    required String phone,
    required String password,
  }) async {
    final result = await _repo.register(
      name: name,
      phone: phone,
      password: password,
    );
    state = AuthOtpPending(
      phone: result.phone,
      isRegistering: true,
      debugOtp: result.debugOtp,
    );
  }

  // ── OTP verification ──────────────────────────────────────────────────────

  /// Throws on wrong code so the OTP screen can shake the boxes.
  Future<void> verifyOtp({required String code}) async {
    final pending = state as AuthOtpPending;
    final deviceId = await _secure.readDeviceId();
    final result = await _repo.verifyOtp(
      phone: pending.phone,
      code: code,
      deviceId: deviceId,
    );
    _ref.read(authTokenProvider.notifier).set(result.accessToken);
    await _secure.saveRefreshToken(result.refreshToken);
    state = AuthAuthenticated(me: result.me);
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    final token = _ref.read(authTokenProvider);
    if (token != null) {
      try {
        final deviceId = await _secure.readDeviceId();
        await _repo.logout(accessToken: token, deviceId: deviceId);
      } catch (_) {
        // Always clear locally, even if server call fails.
      }
    }
    _ref.read(authTokenProvider.notifier).clear();
    await _secure.deleteRefreshToken();
    state = const AuthUnauthenticated();
  }

  /// Called by the Dio interceptor when a token refresh fails mid-flight.
  /// Does NOT await async cleanup — it's fire-and-forget by design.
  void forceSignOut() {
    _ref.read(authTokenProvider.notifier).clear();
    state = const AuthUnauthenticated();
    // Delete the stale refresh token in the background.
    _secure.deleteRefreshToken();
  }

  // ── Profile sync ──────────────────────────────────────────────────────────

  /// Updates the cached User inside the Authenticated state, e.g. after name
  /// or avatar changes from ProfileScreen.
  void updateCachedUser(dynamic user) {
    final current = state;
    if (current is AuthAuthenticated) {
      state = AuthAuthenticated(me: user as dynamic);
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(secureStorageProvider),
    ref,
  );
});
